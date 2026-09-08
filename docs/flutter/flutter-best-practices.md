# Architecture recommendations and resources

Recommendations for building scalable Flutter applications.

This page presents architecture best practices, why they matter, and whether we recommend them for your Flutter application. You should treat these recommendations as recommendations, and not steadfast rules, and you should adapt them to your app's unique requirements.

The best practices on this page have a priority, which reflects how strongly the Flutter team recommends it:

*   **Strongly recommend:** You should always implement this recommendation if you're starting to build a new application. You should strongly consider refactoring an existing app to implement this practice unless doing so would fundamentally clash with your current approach.
*   **Recommend:** This practice will likely improve your app.
*   **Conditional:** This practice can improve your app in certain circumstances.

---

## Separation of concerns

You should separate your app into a UI layer and a data layer. Within those layers, you should further separate logic into classes by responsibility.

**Use clearly defined data and UI layers.**
*Priority: Strongly recommend*
Separation of concerns is the most important architectural principle. The data layer exposes application data to the rest of the app, and contains most of the business logic in your application. The UI layer displays application data and listens for user events from users. The UI layer contains separate classes for UI logic and widgets.

**Use the repository pattern in the data layer.**
*Priority: Strongly recommend*
The repository pattern is a software design pattern that isolates the data access logic from the rest of the application. It creates an abstraction layer between the application's business logic and the underlying data storage mechanisms (databases, APIs, file systems, etc.). In practice, this means creating Repository classes and Service classes.

**Use ViewModels and Views in the UI layer. (MVVM)**
*Priority: Strongly recommend*
Separation of concerns is the most important architectural principle. This particular separation makes your code much less error prone because your widgets remain "dumb".

**Use `ChangeNotifiers` and `Listenables` to handle widget updates.**
*Priority: Conditional*
The `ChangeNotifier` API is part of the Flutter SDK, and is a convenient way to have your widgets observe changes in your ViewModels. There are many options to handle state-management, and ultimately the decision comes down to personal preference. Read about [our ChangeNotifier recommendation](/get-started/fwe/state-management) or [other popular options](https://docs.flutter.dev/data-and-backend/state-mgmt/options).

**Do not put logic in widgets.**
*Priority: Strongly recommend*
Logic should be encapsulated in methods on the ViewModel. The only logic a view should contain is:
*   Simple if-statements to show and hide widgets based on a flag or nullable field in the ViewModel
*   Animation logic that relies on the widget to calculate
*   Layout logic based on device information, like screen size or orientation
*   Simple routing logic

**Use a domain layer.**
*Priority: Conditional*
A domain layer is only needed if your application has exceeding complex logic that crowds your ViewModels, or if you find yourself repeating logic in ViewModels. In very large apps, use-cases are useful, but in most apps they add unnecessary overhead. Use in apps with complex logic requirements.

**UI Suggestions**
*Priority: Recommend*
Organize your UI using stacks and clear background/foreground layers. Use modals and panels for new elements. This provides a sense of depth and allows elemnts to persist in background, dimming as other panels and modals overlay them. Maintain state discipline. Render content within containers optimistically, with fallback to error or *not available* indicators

**Surface errors clearly and centralize error handling.**
*Priority: Strongly recommend*
Let all errors route through an error handling surface, and display as popups, toasts, and element states as appropriate. It's very important that all errors are surfaced to the users, with UI reflecting severity organically.

**Local-First Principle.**
*Priority: Strongly recommend*
All UI, state, and core functionality should operate locally by default. User interactions (like sending a message) should reflect in the UI instantly using local state. Cloud synchronization should happen in the background. Delays, progress, or failures in cloud sync should be treated as augmentative information (e.g., small status indicators) rather than blocking states. The application should remain fully functional and responsive even with high latency or no connectivity.

---

## Handling data

Handling data with care makes your code easier to understand, less error prone, and prevents malformed or unexpected data from being created.

**Use unidirectional data flow.**
*Priority: Strongly recommend*
Data updates should only flow from the data layer to the UI layer. Interactions in the UI layer are sent to the data layer where they're processed.

**Use `Commands` to handle events from user interaction.**
*Priority: Recommend*
Commands prevent rendering errors in your app, and standardize how the UI layer sends events to the data layer. Read about commands in the [architecture case study](/app-architecture/guide).

**Use immutable data models.**
*Priority: Strongly recommend*
Immutable data is crucial in ensuring that any necessary changes occur only in the proper place, usually the data or domain layer. Because immutable objects can't be modified after creation, you must create a new instance to reflect changes. This process prevents accidental updates in the UI layer and supports a clear, unidirectional data flow.

**Use freezed or built_value to generate immutable data models.**
*Priority: Recommend*
You can use packages to help generate useful functionality in your data models, [freezed](https://pub.dev/packages/freezed) or [built_value](https://pub.dev/packages/built_value). These can generate common model methods like JSON serialization/deserialization, deep equality checking and copy methods. These code generation packages can add significant build time to your applications if you have a lot of models.

**Create separate API models and domain models.**
*Priority: Conditional*
Using separate models adds verbosity, but prevents complexity in ViewModels and use-cases. Use in large apps.

---

## App structure

Well organized code benefits both the health of the app itself, and the team working on the code.

**Use dependency injection.**
*Priority: Strongly recommend*
Dependency injection prevents your app from having globally accessible objects, which makes your code less error prone. We recommend you use the [provider](https://pub.dev/packages/provider) package to handle dependency injection.

**Use go_router for navigation.**
*Priority: Recommend*
[go_router](https://pub.dev/packages/go_router) is the preferred way to write 90% of Flutter applications. There are some specific use-cases that go_router doesn't solve, in which case you can use the [Flutter Navigator API](https://docs.flutter.dev/ui/navigation) directly or try other packages found on [pub.dev](https://pub.dev).

**Use standardized naming conventions for classes, files and directories.**
*Priority: Recommend*
We recommend naming classes for the architectural component they represent. For example, you may have the following classes:
*   HomeViewModel
*   HomeScreen
*   UserRepository
*   ClientApiService

For clarity, we do not recommend using names that can be confused with objects from the Flutter SDK. For example, you should put your shared widgets in a directory called `ui/core/`, rather than a directory called `/widgets`.

**Use abstract repository classes**
*Priority: Strongly recommend*
Repository classes are the sources of truth for all data in your app, and facilitate communication with external APIs. Creating abstract repository classes allows you to create different implementations, which can be used for different app environments, such as "development" and "staging".

**Prefer flat project structures.**
*Priority: Recommend*
Generally, "flatter is better". Avoid deeply nested workspace structures (e.g., `apps/my_app`, `packages/my_package`) unless you are managing a complex mono-repo with multiple high-level applications. For most projects, keeping the primary `pubspec.yaml` and `lib/` directory at the project root ensures standard tooling (like `flutter run` or IDE plugins) works as expected without extra configuration.

---

## Testing

Good testing practices makes your app flexible. It also makes it straightforward and low risk to add new logic and new UI.

**Test architectural components separately, and together.**
*Priority: Strongly recommend*
*   Write unit tests for every service, repository and ViewModel class. These tests should test the logic of every method individually.
*   Write widget tests for views. Testing routing and dependency injection are particularly important.

**Make fakes for testing (and write code that takes advantage of fakes.)**
*Priority: Strongly recommend*
Fakes aren't concerned with the inner workings of any given method as much as they're concerned with inputs and outputs. If you have this in mind while writing application code, you're forced to write modular, lightweight functions and classes with well defined inputs and outputs.

---

## Recommended resources

*   **Code and templates**
    *   [Compass app source code](https://github.com/flutter/samples/tree/main/compass_app) - Source code of a full-featured, robust Flutter application that implements many of these recommendations.
    *   [very_good_cli](https://cli.vgv.dev/) - A Flutter application template made by the Flutter experts Very Good Ventures. This template generates a similar app structure.
*   **Documentation**
    *   [Very Good Engineering architecture documentation](https://engineering.verygood.ventures/architecture/architecture/) - Very Good Engineering is a documentation site by VGV that has technical articles, demos, and open-sourced projects. It includes documentation on architecting Flutter applications.
*   **Tooling**
    *   [Flutter developer tools](/tools/devtools) - DevTools is a suite of performance and debugging tools for Dart and Flutter.
    *   [flutter_lints](https://pub.dev/packages/flutter_lints) - A package that contains the lints for Flutter apps recommended by the Flutter team. Use this package to encourage good coding practices across a team.

---

# Best practices for adaptive design

> Summary of some of the best practices for adaptive design.

Recommended best practices for adaptive design include:

## Design considerations

### Break down your widgets

While designing your app, try to break down large,
complex widgets into smaller, simpler ones.

Refactoring widgets can reduce the complexity of
adopting an adaptive UI by sharing core pieces of code.
There are other benefits as well:

* On the performance side, having lots of small `const`
  widgets improves rebuild times over having large,
  complex widgets.
* Flutter can reuse `const` widget instances,
  while a larger complex widget has to be set up
  for every rebuild.
* From a code health perspective, organizing your UI
  into smaller bite sized pieces helps keep the complexity
  of each `Widget` down. A less-complex `Widget` is more readable,
  easier to refactor, and less likely to have surprising behavior.

To learn more, check out the 3 steps of
adaptive design in [General approach][].

[General approach]: /ui/adaptive-responsive/general

### Design to the strengths of each form factor

Beyond screen size, you should also spend time
considering the unique strengths and weaknesses
of different form factors. It isn't always ideal
for your multiplatform app to offer identical
functionality everywhere. Consider whether it makes
sense to focus on specific capabilities,
or even remove certain features, on some device categories.

For example, mobile devices are portable and have cameras,
but they aren't well suited for detailed creative work.
With this in mind, you might focus more on capturing content
and tagging it with location data for a mobile UI,
but focus on organizing or manipulating that content
for a tablet or desktop UI.

Another example is leveraging the web's extremely low barrier
for sharing. If you're deploying a web app,
decide which [deep links][] to support,
and design your navigation routes with those in mind.

The key takeaway here is to think about what each
platform does best and see if there are unique capabilities
you can leverage.

[deep links]: /ui/navigation/deep-linking

### Solve touch first

Building a great touch UI can often be more difficult
than a traditional desktop UI due, in part,
to the lack of input accelerators like right-click,
scroll wheel, or keyboard shortcuts.

One way to approach this challenge is to focus initially
on a great touch-oriented UI. You can still do most of
your testing using the desktop target for its iteration speed.
But, remember to switch frequently to a mobile device to
verify that everything feels right.

After you have the touch interface polished, you can tweak
the visual density for mouse users, and then layer on all
the additional inputs. Approach these other inputs as
accelerator—alternatives that make a task faster.
The important thing to consider is what a user expects
when using a particular input device,
and work to reflect that in your app.

## Implementation details

### Don't lock the orientation of your app.

An adaptive app should look good on windows of
different sizes and shapes. While locking an app
to portrait mode on phones can help narrow the scope
of a minimum viable product, it can increase the
effort required to make the app adaptive in the future.

For example, the assumption that phones will only
render your app in a full screen portrait mode is
not a guarantee. Multi window app support is becoming common,
and foldables have many use cases that work best with
multiple apps running side by side.

If you absolutely must lock your app in portrait mode (but don't),
use the `Display` API instead of something like `MediaQuery`
to get the physical dimensions of the screen.

To summarize:

  * Locked screens can be [an accessibility issue][] for some users
  * Android large format tiers require portrait and landscape
    support at the [lowest level][].
  * Android devices can [override a locked screen][]
  * Apple guidelines say [aim to support both orientations][]

[an accessibility issue]: https://www.w3.org/WAI/WCAG21/Understanding/orientation.html
[aim to support both orientations]: https://www.w3.org/WAI/WCAG21/Understanding/orientation.html
[lowest level]:  https://developer.android.com/docs/quality-guidelines/large-screen-app-quality#T3-8
[override a locked screen]: https://developer.android.com/guide/topics/large-screens/large-screen-compatibility-mode#per-app_overrides

### Avoid device orientation-based layouts

Avoid using `MediaQuery`'s orientation field
or `OrientationBuilder` near the top of your widget tree
to switch between different app layouts. This is
similar to the guidance of not checking device types
to determine screen size. The device's orientation also
doesn't necessarily inform you of how much space your
app window has.

Instead, use `MediaQuery`'s `sizeOf` or `LayoutBuilder`,
as discussed in the [General approach][] page.
Then use adaptive breakpoints like the ones that
[Material][] recommends.

[General approach]: /ui/adaptive-responsive/general#
[Material]: https://m3.material.io/foundations/layout/applying-layout/window-size-classes

### Don't gobble up all of the horizontal space

Apps that use the full width of the window to
display boxes or text fields don't play well
when these apps run on large screens.

To learn how to avoid this,
check out [Layout with GridView][].

[Layout with GridView]: /ui/adaptive-responsive/large-screens#layout-with-gridview

### Avoid checking for hardware types

Avoid writing code that checks whether the device you're
running on is a "phone" or a "tablet", or any other type
of device when making layout decisions.

What space your app is actually given to render in
isn't always tied to the full screen size of the device.
Flutter can run on many different platforms,
and your app might be running in a resizeable window on ChromeOS,
side by side with another app on tablets in a multi-window mode,
or even in a picture-in-picture on phones.
Therefore, device type and app window size aren't
really strongly connected.

Instead, use `MediaQuery` to get the size of the window
your app is currently running in.

This isn't only helpful for UI code.
To learn how abstracting out device
capabilities can help your business logic code,
check out the 2022 Google I/O talk,
[Flutter lessons for federated plugin development][].

[Flutter lessons for federated plugin development]: https://www.youtube.com/watch?v=GAnSNplNpCA

### Support a variety of input devices

Apps should support basic mice, trackpads,
and keyboard shortcuts. The most common user
flows should support keyboard navigation
to ensure accessibility. In particular,
your app follow accessible best practices
for keyboards on large devices.

The Material library provides widgets with
excellent default behavior for touch, mouse,
and keyboard interaction.

To learn how to add this support to custom widgets,
check out [User input & accessibility][].

[User input & accessibility]: /ui/adaptive-responsive/input

### Restore List state

To maintain the scroll position in a list
that doesn't change its layout when the
device's orientation changes,
use the [`PageStorageKey`][] class.
[`PageStorageKey`][] persists the
widget state in storage after the widget is
destroyed and restores state when recreated.

You can see an example of this in the [Wonderous app][],
where it stores the list's state in the
`SingleChildScrollView` widget.

If the `List` widget changes its layout
when the device's orientation changes,
you might have to do a bit of math ([example][])
to change the scroll position on screen rotation.

[example]: https://github.com/gskinnerTeam/flutter-wonderous-app/blob/34e49a08084fbbe69ed67be948ab00ef23819313/lib/ui/screens/collection/widgets/_collection_list.dart#L39
[`PageStorageKey`]: https://api.flutter.dev/flutter/widgets/PageStorageKey-class.html
[Wonderous app]: https://github.com/gskinnerTeam/flutter-wonderous-app/blob/8a29d6709668980340b1b59c3d3588f123edd4d8/lib/ui/screens/wonder_events/widgets/_events_list.dart#L64

## Save app state

Apps should retain or restore [app state][]
as the device rotates, changes window size,
or folds and unfolds.
By default, an app should maintain state.

If your app loses state during device configuration,
verify that the plugins and native extensions
that your app uses support the
device type, such as a large screen.
Some native extensions might lose state when the
device changes position.

For more information on a real-world case
where this occurred, check out
[Problem: Folding/unfolding causes state loss][state-loss]
in [Developing Flutter apps for Large screens][article],
a post on the Flutter blog.

[app state]: https://developer.android.com/jetpack/compose/state#store-state
[article]: https://blog.flutter.dev/developing-flutter-apps-for-large-screens-53b7b0e17f10
[state-loss]: https://blog.flutter.dev/developing-flutter-apps-for-large-screens-53b7b0e17f10#:~:text=Problem%3A%20Folding/Unfolding%20causes%20state%2Dloss

---

## Feedback

As this section of the website is evolving, we [welcome your feedback](https://google.qualtrics.com/jfe/form/SV_4T0XuR9Ts29acw6?page=%22recommendations%22)!