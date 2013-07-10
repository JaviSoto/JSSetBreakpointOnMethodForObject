//
//  JSSetBreakpointOnMethodForObject.m
//
//  Created by Javier Soto on 7/9/13.
//
//

#import <Foundation/Foundation.h>

#if DEBUG

/**
 Makes the debugger stop when the method `selector` is called on `object`.
 */
extern void js_setBreakpointOnMethodForObject(id object, SEL selector);

/**
 Stops making the debugger stop when any method is called on `object`.
 */
extern void js_removeBreakpointsForObject(id object);

#endif