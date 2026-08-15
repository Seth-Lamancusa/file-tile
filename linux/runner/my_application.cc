#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Method channel used to hand a `filetile://open?path=...` deep link's path
// to Dart. Fired both on a cold start with a URL and when a second instance
// forwards its URL to this (the primary) instance via GApplication's D-Bus
// activation.
static const char* kOpenPathChannel = "filetile/open_path";
static const char* kOpenPathMethod = "openPath";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlView* view;
  FlMethodChannel* open_path_channel;
  // Set when a path arrives before the first Flutter frame has rendered
  // (i.e. this instance is being launched fresh via a filetile:// URL).
  // Flushed once the engine is ready to receive channel calls.
  gchar* pending_path;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void send_open_path(MyApplication* self, const gchar* path) {
  if (self->open_path_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string(path);
  fl_method_channel_invoke_method(self->open_path_channel, kOpenPathMethod,
                                   args, nullptr, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));

  if (self->pending_path != nullptr) {
    send_open_path(self, self->pending_path);
    g_clear_pointer(&self->pending_path, g_free);
  }
}

// Extracts the `path` query parameter from a `filetile://open?path=...` URI.
// Returns a newly-allocated, percent-decoded string, or nullptr if absent.
static gchar* extract_path_from_uri(const char* uri) {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* scheme = g_uri_parse_scheme(uri);
  if (scheme == nullptr || g_strcmp0(scheme, "filetile") != 0) {
    g_warning("Ignoring open request for unsupported URI: %s", uri);
    return nullptr;
  }

  g_autoptr(GUri) parsed =
      g_uri_parse(uri, G_URI_FLAGS_ENCODED_QUERY, &error);
  if (parsed == nullptr) {
    g_warning("Failed to parse filetile URI '%s': %s", uri, error->message);
    return nullptr;
  }

  const char* query = g_uri_get_query(parsed);
  if (query == nullptr) return nullptr;

  g_autoptr(GHashTable) params =
      g_uri_parse_params(query, -1, "&", G_URI_PARAMS_NONE, &error);
  if (params == nullptr) {
    g_warning("Failed to parse filetile URI query '%s': %s", query,
              error->message);
    return nullptr;
  }

  const gchar* path = static_cast<const gchar*>(g_hash_table_lookup(params, "path"));
  return path != nullptr ? g_strdup(path) : nullptr;
}

// Creates the application window and Flutter view if they don't already
// exist. Safe to call from both `activate` and `open`.
static void ensure_window(MyApplication* self) {
  GApplication* application = G_APPLICATION(self);
  if (gtk_application_get_windows(GTK_APPLICATION(application)) != nullptr) {
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "File Tile");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "File Tile");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  self->open_path_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kOpenPathChannel, FL_METHOD_CODEC(fl_standard_method_codec_new()));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  ensure_window(MY_APPLICATION(application));
}

// Implements GApplication::open. Invoked instead of `activate` when the
// application is launched (or, for an already-running primary instance,
// re-invoked via D-Bus) with one or more URIs to open -- i.e. a
// `filetile://open?path=...` deep link from doc-block.
static void my_application_open(GApplication* application, GFile** files,
                                 gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  gboolean window_existed =
      gtk_application_get_windows(GTK_APPLICATION(application)) != nullptr;

  ensure_window(self);

  // Bring the (possibly pre-existing) window to the front.
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    GtkWindow* window = GTK_WINDOW(windows->data);
    gtk_window_deiconify(window);
    gtk_window_present(window);
  }

  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    g_autofree gchar* path = extract_path_from_uri(uri);
    if (path == nullptr) continue;

    if (window_existed) {
      // Flutter engine is already running; safe to invoke the channel now.
      send_open_path(self, path);
    } else {
      // Cold start: defer until the first frame has rendered and the
      // channel handler on the Dart side has had a chance to register.
      g_free(self->pending_path);
      self->pending_path = g_strdup(path);
    }
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // A `filetile://...` URI passed on the command line (e.g. by a launcher
  // invoking Exec=file_tile %u from the .desktop URL handler) must
  // go through GApplication::open, not ::activate, so it reaches
  // my_application_open on both a cold start and when forwarded via D-Bus
  // to an already-running primary instance. Anything else is a normal
  // launch with no deep link to handle.
  gchar** remaining_args = self->dart_entrypoint_arguments;
  gint n_uris = 0;
  for (gint i = 0; remaining_args != nullptr && remaining_args[i] != nullptr; i++) {
    g_autofree gchar* scheme = g_uri_parse_scheme(remaining_args[i]);
    if (g_strcmp0(scheme, "filetile") == 0) n_uris++;
  }

  if (n_uris > 0) {
    GFile** files = g_new0(GFile*, n_uris);
    gint j = 0;
    for (gint i = 0; remaining_args[i] != nullptr; i++) {
      g_autofree gchar* scheme = g_uri_parse_scheme(remaining_args[i]);
      if (g_strcmp0(scheme, "filetile") == 0) {
        files[j++] = g_file_new_for_uri(remaining_args[i]);
      }
    }
    g_application_open(application, files, n_uris, "");
    for (gint i = 0; i < n_uris; i++) g_object_unref(files[i]);
    g_free(files);
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->pending_path, g_free);
  g_clear_object(&self->open_path_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // No G_APPLICATION_NON_UNIQUE here: dropping it is what makes GApplication
  // enforce single-instance via D-Bus activation, and HANDLES_OPEN is what
  // routes a `filetile://` launch (on this or a second invocation) through
  // my_application_open instead of my_application_activate.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
