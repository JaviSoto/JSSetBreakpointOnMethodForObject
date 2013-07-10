//
//  JSSetBreakpointOnMethodForObject.m
//
//  Created by Javier Soto on 7/9/13.
//
//

#import "JSSetBreakpointOnMethodForObject.h"

#if DEBUG

#import "MSDebugger.h"

#import <objc/runtime.h>
#import <objc/message.h>

static BOOL _js_hasBreakpointsEnabled(id self, SEL _cmd)
{
    return YES;
}

static SEL _js_hasBreakpointsEnabledSelector(void)
{
    return NSSelectorFromString(@"_js_hasBreakpointsEnabled");
}

static BOOL js_objectIsOfDynamicSubclass(id object)
{
    if (!object)
    {
        return NO;
    }

    SEL selector = _js_hasBreakpointsEnabledSelector();

    if (class_respondsToSelector(object_getClass(object), selector))
    {
        return ((BOOL(*)(id, SEL))objc_msgSend)((id)object, selector);
    }

    return NO;
}

static __inline__ NSString *js_dynamicSubclassNameForObject(id object)
{
    static NSString *const JSDynamicSubclassPrefix = @"__JSMethodBreakpoint_";

    return [NSString stringWithFormat:@"%@%@", JSDynamicSubclassPrefix, NSStringFromClass([object class])];
}

// We override class to make the dynamic subclass objects pose as the normal class
static Class js_class(id self, SEL _cmd)
{
    Class thisClass = object_getClass(self);

    return class_getSuperclass(thisClass);
}

/**
 This is the method that is called instead of the original selector.
 It has to do two things:
 1. Pause the debugger.
 2. Call the original implementation of the object (the one of the parent class).
*/
static void catchEmAllMethodTrampoline(id self, SEL _cmd, NSInvocation *invocation)
{
    MSBreakIntoDebugger();

    IMP parentInvocation = [[self class] instanceMethodForSelector:invocation.selector];
    // Private API: -[NSInvocation invokeUsingIMP:]
    [invocation performSelector:NSSelectorFromString(@"invokeUsingIMP:") withObject:(id)parentInvocation];
}

#define ADD_NEW_METHOD(class, selector, function_pointer) class_addMethod(class, selector, (IMP)function_pointer, @encode(typeof(function_pointer)));

extern void js_setBreakpointOnMethodForObject(id object, SEL selector)
{
    NSCParameterAssert(object);

    // Add a dynamic subclass for that object

    // 1. Does the subclass already exist?
    NSString *subclassName = js_dynamicSubclassNameForObject(object);
    Class subclass = NSClassFromString(subclassName);

    // 2. Doesn't exist. Creating the dynamic subclass
    if (!subclass)
    {
        Class parentClass = [object class];
        subclass = objc_allocateClassPair(parentClass, [subclassName cStringUsingEncoding:NSASCIIStringEncoding], 0);

        NSCAssert(subclass, @"Could not create dynamic subclass for object %@", object);

        objc_registerClassPair(subclass);

        ADD_NEW_METHOD(subclass, @selector(class), js_class);
        ADD_NEW_METHOD(subclass, _js_hasBreakpointsEnabledSelector(), _js_hasBreakpointsEnabled);
    }

    Method *method = class_getInstanceMethod(object_getClass(object), selector);
    class_addMethod(subclass, selector, _objc_msgForward, method_getTypeEncoding(method));

    // XXX: It's necessary to first check if -forwardInvocation: exists.
    // If it exists, its IMP would need to be captured and used when called with
    // an invocation who's selector doesn't correspond to an intercepted method.
    class_addMethod(subclass, @selector(forwardInvocation:), catchEmAllMethodTrampoline, "v@:@");

    // 3. Make the object of that subclass
    object_setClass(object, subclass);
}

extern void js_removeBreakpointsForObject(id object)
{
    NSCParameterAssert(object);

    if (js_objectIsOfDynamicSubclass(object))
    {
        // Simply set the class to the parent (the one posed as by -class) so that it doesn't have the modified method implementations
        object_setClass(object, [object class]);

        // Note: The dynamic subclass will still exist.
    }
}

#endif