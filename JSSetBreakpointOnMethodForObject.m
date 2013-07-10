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

#define _GetPossibleParameterValue(index, encodedType, possibleType) do { \
                NSUInteger parameterSize = 0; \
                if (strcmp(parameterType, @encode(possibleType)) == 0) \
                { \
                    parameterSize = sizeof(possibleType); \
                    parameterBuffer = malloc(parameterSize); \
                    possibleType object = va_arg(args, possibleType); \
                    *(possibleType *)parameterBuffer = object; \
                } \
        } while(0)

/**
 This is the method that is called instead of the original selector.
 It has to do two things:
 1. Pause the debugger.
 2. Call the original implementation of the object (the one of the parent class).
*/
static id catchEmAllMethodTrampoline(id self, SEL _cmd, ...)
{
    MSBreakIntoDebugger();

    NSMethodSignature *methodSignature = [[self class] instanceMethodSignatureForSelector:_cmd];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    invocation.target = self;
    invocation.selector = _cmd;

    const NSUInteger numberOfArguments = methodSignature.numberOfArguments;
    if (numberOfArguments > 2)
    {
        va_list args;
        va_start(args, _cmd);

        for (NSUInteger parameterIndex = 2; parameterIndex < numberOfArguments; parameterIndex++)
        {
            void *parameterBuffer = NULL;
            const char *parameterType = [methodSignature getArgumentTypeAtIndex:parameterIndex];

            _GetPossibleParameterValue(parameterIndex, parameterType, id);
            _GetPossibleParameterValue(parameterIndex, parameterType, int);

            NSCAssert(parameterBuffer, @"Couldn't find type for argument at index %d (%s) on method with selector %@", parameterIndex, parameterType, NSStringFromSelector(_cmd));

            [invocation setArgument:parameterBuffer atIndex:(NSInteger)parameterIndex];
        }
    }

    IMP parentInvocation = [[self class] instanceMethodForSelector:_cmd];
    // Private API: -[NSInvocation invokeUsingIMP:]
    [invocation performSelector:NSSelectorFromString(@"invokeUsingIMP:") withObject:(id)parentInvocation];

    NSUInteger returnTypeSize = methodSignature.methodReturnLength;

    if (returnTypeSize > 0)
    {
        void *returnValueBuffer = (void *)malloc(returnTypeSize);
        [invocation getReturnValue:returnValueBuffer];

        return returnValueBuffer;
    }
    else
    {
        return nil;
    }
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

    ADD_NEW_METHOD(subclass, selector, catchEmAllMethodTrampoline);

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