GCDMulticastDelegate
===========

[![Platform](http://img.shields.io/badge/platform-ios-blue.svg?style=flat
)](https://developer.apple.com/iphone/index.action)
[![Language](http://img.shields.io/badge/language-objc-brightgreen.svg?style=flat
)](https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC)
[![License](http://img.shields.io/badge/license-BSD-lightgrey.svg?style=flat
)](http://choosealicense.com/licenses/bsd-2-clause)

GCDMulticastDelegate extracted from XMPPFramework

* **What is a "multicast delegate"?**
* **Why is it used?**
* **And why not a normal delegate or notifications?**

## Introduction

There are two common callback systems that Apple uses:

-   delegates
-   notifications

Delegates are really simple and straightforward. The user registers itself as a delegate. And then implements the delegate methods that it needs.
```objective-c
[worker setDelegate:self];

- (void)workerDidFinish:(Worker *)sender
{
}

- (void)worker:(Worker *)sender didFinishSubTask:(id)subtask inDuration:(NSTimeInterval)elapsed
{
}

- (BOOL)worker:(Worker *)sender shouldPerformSubTask:(id)subtask
{
}
```

Notifications are also fairly simple, but require a bit more setup. The user has to register, individually, for each notification type that it's interested in:
```objective-c
[[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(workerDidFinish:)
                                             name:WorkerDidFinishNotification
                                           object:nil];

[[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(workerDidFinishSubTask:)
                                             name:WorkerDidFinishSubTaskNotification
                                           object:nil];

- (void)workerDidFinish:(NSNotification *)notification
{
    Worker *sender = [notification object];
}

- (void)workerDidFinishSubTask:(NSNotification *)notification
{
    Worker *sender = [notification object];
    id subtask = [[notification userInfo] objectForKey:@"subtask"];
    NSTimeInterval elapsed = [[[notification userInfo] objectForKey"duration"] doubleValue];
}
```

Notice that we have to extract parameters from the notification object. Sometimes this requires extracting the parameters from a dictionary, which means one has to know the proper keys to the dictionary.

Also notice that the 3rd delegate method is **impossible** to do via notifications, because the notification system does not allow for return variables.

There are pros and cons of each solution.

Delegate pros:

-   Much easier to register for multiple callbacks
-   Much easier (and far simpler) to use when there are multiple parameters
-   Allows for return variables

Delegate cons:

-   There can only be a single delegate

Notification pros:

-   Multiple objects can register for the same notification

Notification cons:

-   Annoying to register for multiple callbacks
-   Extremely annoying to extract parameters from a dictionary
-   Impossible to use when a return variable is needed

## What are the requirements for XMPPFramework?

1. **The xmpp framework must be able to broadcast events to multiple listeners.** <br/>
     Consider something as simple as a message. There might be multiple listeners such as a chat window, a history logger, and a pop-up notification system.

2. **The xmpp framework must be easily extensible.** <br/>
    It should be able to support the large number of [XEP's](http://xmpp.org/xmpp-protocols/xmpp-extensions/), as well as any custom xmpp protocol developers wish to implement on top of it. In other words, whatever solution we pick should be easy to use on both the broadcasting side and the listener side.

3. **The system we choose must support return variables.** <br/>
    A perfect example is the IQ processing mandate of the XMPP RFC. If a client receives an IQ of type 'get' or 'set', and doesn't know how to process it, it MUST return an IQ of type 'error'. This must work properly in the face of multiple plugins.

4. **The system we choose must help maintain thread-safety** <br/>
    The xmpp framework is massively parallel. Socket IO, xml parsing, xmpp stanza routing, modules, disk IO, and delegates can all run in their own GCD queue, which on a multicore device may mean many tasks are running simultaneously on different threads. The system shouldn't make us jump through hoops to maintain parallelism and thread-safety.

So it would seem that neither the delegate nor notification pattern exactly fit our requirements. And thus we created the GCDMulticastDelegate class.

## What's it look like?

It's very simple. As a client, you simply do something like this:
```objective-c
// Add myself as a delegate, and tell xmppStream to invoke my delegate methods on the main thread
[xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];

// Then just implement whatever delegate methods you need like normal
- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
   ...
}
```

And that's all there is to it! As you can see, it's very similar to the traditional delegate pattern, but is extended to allow you to specify thread-specific information.

And if you later decide that you'd like to move some of your processing off the main thread? Well, that' super easy too:

```objective-c
// Handle most stuff on the main thread
[xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];

// But do that one slow thing on a background queue so it doesn't slow down the UI anymore
[xmppStream addDelegate:bgProcessor delegateQueue:bgProcessorQueue];
```

In an environment such as the iPhone, this becomes a very powerful tool for maintaining the performance of your app.

## I don't wanna...

MulticastDelegate is used in XMPPStream because it is the right tool for the job. It is also used in various other parts of the framework because it makes life easier for the broadcaster and listener(s).

A word of caution:

MulticastDelegate is a new paradigm for many developers. I understand that sometimes **new = scary**, and you may be tempted to ignore it simply because its new or because you don't fully understand it right now. But believe me when I say that we didn't invent GCDMulticastDelegate because we thought it would be cool to create a new paradigm. We did it out of necessity. We did it because it was the best solution to the problem. So give it a try and I think you'll be pleasantly surprised.

## How would I use it in my own plugin?

In order to use a multicast delegate, **as a broadcaster**, you would declare it and initialize it like:
```objective-c
GCDMulticastDelegate <MyPluginDelegate> *multicastDelegate;
multicastDelegate = (GCDMulticastDelegate <MyPluginDelegate> *)[[GCDMulticastDelegate alloc] init];
```

Then add methods that allow others to add/remove themselves from the delegate list:
```objective-c
- (void)addDelegate:(id)delegate delegateQueue:(dispatch_queue_t)delegateQueue
{
    [multicastDelegate addDelegate:delegate delegateQueue:delegateQueue];
}

- (void)removeDelegate:(id)delegate delegateQueue:(dispatch_queue_t)delegateQueue
{
    [multicastDelegate removeDelegate:delegate delegateQueue:delegateQueue];
}
```
_(The above methods are automatically implemented for you if you're extending XMPPModule.)_

When you want to issue a delegate method, to all the registered delegates, you can simply do this:
```objective-c
[multicastDelegate worker:self didFinishSubTask:subtask inDuration:elapsed];
```

It's that simple. The multicast delegate invoke all the delegates, each on their associated dispatch_queue via a dispatch_async() call.

## What about return variables?

First the theoretical question: How to handle varying responses?<br/>
For example, consider the following delegate method:
```objective-c
- (BOOL)worker:(Worker *)sender shouldPerformSubTask:(id)subtask;
```

If there are 3 delegates, and 2 return YES while 1 returns NO, how do we handle it?

It becomes clear that the correct functionality depends on the situation. In this particular situation, if ANY of our delegates say NO, then we shouldn't perform the subtask.

Second is the technical question: How do I implement it?

Each "node" in the GCDMulticastDelegate list contains both a delegate and the associated dispatch_queue that the delegate is to be invoked on. So we iterate through the list, but... we don't want to dispatch_sync or otherwise block our queue. Why not?

We're running in **dispatch\_queue\_a**, while the delegate is running in **dispatch\_queue\_b**. So if we block via something like dispatch_sync(dispatch_queue_b, block), and dispatch_queue_b is blocking on us (maybe by accessing some property of ours), we get a **deadlock**.

The code sample below is a little more complex than the typical one-liner for delegate methods without a return type. But in return for the additional complexity, we get massive parallelization throughout the framework. (And return variables aren't very common.)

### Implementing the multicast delegate return pattern

```objective-c
// Delegate rules:
// 
// If ANY of the delegates return NO, then the result is NO.
// Otherwise the result is YES.

SEL selector = @selector(worker:shouldPerformSubTask:);

NSUInteger delegateCount = [multicastDelegate countForSelector:selector];
if (delegateCount == 0)
{
    // No delegates implement the selector - default is YES
    [self continuePerformSubTask:YES];
}
else
{
    // Query the delegate(s)
    GCDMulticastDelegateEnumerator *delegateEnumerator = [multicastDelegate delegateEnumerator];

    dispatch_semaphore_t delSemaphore = dispatch_semaphore_create(0);
    dispatch_group_t delGroup = dispatch_group_create();
    
    id del;
    dispatch_queue_t dq;

    while ([delegateEnumerator getNextDelegate:&del delegateQueue:&dq forSelector:selector])
    {
        dispatch_group_async(delGroup, dq, ^{ @autoreleasepool {
            
            if (![del worker:self shouldPerformSubTask:subtask])
            {
                dispatch_semaphore_signal(delSemaphore);
            }
        }});
    }
    
    dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(concurrentQueue, ^{ @autoreleasepool {
        
        // Wait for the delegates to finish
        dispatch_group_wait(delGroup, DISPATCH_TIME_FOREVER);
        
        // What was the delegate response?
        BOOL shouldPerformSubTask = (dispatch_semaphore_wait(delSemaphore, DISPATCH_TIME_NOW) != 0);
        
        dispatch_async(ourQueue, ^{ @autoreleasepool {
            [self continuePerformSubTask:shouldPerformSubTask];
        }});

        dispatch_release(delSemaphore);
        dispatch_release(delGroup);
    }});
}
```

