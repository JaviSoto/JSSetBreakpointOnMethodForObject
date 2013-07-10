JSSetBreakpointOnMethodForObject
================================

C function that makes the debugger stop whenever an Objective-C method with the specified selector is called on the specified object.

```c
extern void js_setBreakpointOnMethodForObject(id object, SEL selector);
```

Simply by calling this C function passing an object and a selector, it will set up a breakpoint that will pause the debugger **only** when that method is called on **that** object, as opposed to adding a symbolic breakpoint on Xcode like `-[UIView setNeedsLayout]`.

### Warning
This uses very dangerous and scary code. Don't compile on production apps (hence the `#if DEBUG`). It also uses private APIs, so it wouldn't be approved by Apple.

### Limited Support
Right now it will only work with Objective-C methods that take parameters of type `id` and `int`, it's trivial to add support for other types, except for structs.
