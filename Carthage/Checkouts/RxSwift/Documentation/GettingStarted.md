Getting Started
===============

This project tries to be consistent with [ReactiveX.io](http://reactivex.io/). The general cross platform documentation and tutorials should also be valid in case of `RxSwift`.

1. [Observables aka Sequences](#observables-aka-sequences)
1. [Disposing](#disposing)
1. [Pipe operator](#pipe-operator)
1. [Implicit `Observable` guarantees](#implicit-observable-guarantees)
1. [Creating your first `Observable` (aka sequence producers)](#creating-your-own-observable-aka-sequence-producers)
1. [Creating an `Observable` that performs work](#creating-an-observable-that-performs-work)
1. [Sharing subscription, refCount and variable operator](#sharing-subscription-refcount-and-variable-operator)
1. [Operators](#operators)
1. [Playgrounds](#playgrounds)
1. [Custom operators](#custom-operators)
1. [Error handling](#error-handling)
1. [Debugging Compile Errors](#debugging-compile-errors)
1. [Debugging](#debugging)
1. [Debugging memory leaks](#debugging-memory-leaks)
1. [KVO](#kvo)
1. [UI layer tips](#ui-layer-tips)
1. [Making HTTP requests](#making-http-requests)
1. [RxDataSourceStarterKit](#rxdatasourcestarterkit)
1. [Examples](Examples.md)

# Observables aka Sequences

## Basics
[Equivalence](MathBehindRx.md) of observer pattern(`Observable<Element>`) and sequences (`Generator`s) is one of the most important things to understand about Rx.

Observer pattern is needed because you want to model asynchronous behavior and
that equivalence enables implementation of high level sequence operations as operators on `Observable`s.

Sequences are a simple, familiar concept that is **easy to visualize**.

People are creatures with huge visual cortexes. When you can visualize something easily, it's a lot easier to reason about.

In that way you can lift a lot of the cognitive load from trying to simulate event state machines inside every Rx operator to high level operations over sequences.

If you don't use Rx and you model async systems, that probably means that your code is full of those state machines and transient states that you need to simulate instead of abstracting them away.

Lists/sequences are probably one of the first concepts mathematicians/programmers learn.

Here is a sequence of numbers


```
--1--2--3--4--5--6--| // it terminates normally
```

Here is another one with characters

```
--a--b--a--a--a---d---X // it terminates with error
```

Some sequences are finite, and some are infinite, like sequence of button taps

```
---tap-tap-------tap--->
```

These diagrams are called marble diagrams.

[http://rxmarbles.com/](http://rxmarbles.com/)

If we were to specify sequence grammar as regular expression it would look something like this

**Next* (Error | Completed)**

This describes the following:

* **sequences can have 0 or more elements**
* **once an `Error` or `Completed` event is received, the sequence can't produce any other element**

Sequences in Rx are described by a push interface (aka callback).

```swift
enum Event<Element>  {
    case Next(Element)      // next element of a sequence
    case Error(ErrorType)   // sequence failed with error
    case Completed          // sequence terminated successfully
}

class Observable<Element> {
    func subscribe(observer: Observer<Element>) -> Disposable
}

protocol ObserverType {
    func on(event: Event<Element>)
}
```

In case you are curious why `ErrorType` isn't generic, you can find explanation [here](DesignRationale.md#why-error-type-isnt-generic).

So the only thing left on the table is `Disposable`.

```swift
protocol Disposable
{
    func dispose()
}
```

## Disposing

There is one additional way an observed sequence can terminate. When you are done with a sequence and want to release all of the resources that were allocated to compute upcoming elements, calling dispose on a subscription will clean this up for you.

Here is an example with `interval` operator. [Definition of `>-` operator is here](DesignRationale.md#pipe-operator)

```swift
let subscription = interval(0.3, scheduler)
            >- subscribe { (e: Event<Int64>) in
                println(e)
            }

NSThread.sleepForTimeInterval(2)

subscription.dispose()

```

This will print:

```
0
1
2
3
4
5
```

One thing to note here is that you usually don't want to manually call `dispose` and this is only educational example. Calling dispose manually is usually bad code smell, and there are better ways to dispose subscriptions. You can either use `DisposeBag`, `ScopedDispose`, `takeUntil` operator or some other mechanism.

So can this code print something after `dispose` call executed? The answer is, it depends.

* If the `scheduler` is **serial scheduler** (`MainScheduler` is serial scheduler) and `dispose` is called on **on the same serial scheduler**, then the answer is **no**.

* otherwise **yes**.

You can find out more about schedulers [here](Schedulers.md).

You simply have two processes happening in parallel.

* one is producing elements
* other is disposing subscription

When you think about it, the question `can something be printed after` doesn't even make sense in case those processes are on different schedulers.

A few more examples just to be sure (`observeOn` is explained [here](Schedulers.md)).

In case you have something like:

```swift
let subscription = interval(0.3, scheduler)
            >- observeOn(MainScheduler.sharedInstance)
            >- subscribe { (e: Event<Int64>) in
                println(e)
            }

// ....

subscription.dispose() // called from main thread

```

**After `dispose` call returns, nothing will be printed. That is a guarantee.**

Also in this case:

```swift
let subscription = interval(0.3, scheduler)
            >- observeOn(serialScheduler)
            >- subscribe { (e: Event<Int64>) in
                println(e)
            }

// ...

subscription.dispose() // executing on same `serialScheduler`

```

**After `dispose` call returns, nothing will be printed. That is a guarantee.**

## Pipe operator

To understand following examples, you will need to understand what is [pipe operator](DesignRationale.md#pipe-operator) (`>-`).

## Implicit `Observable` guarantees

There is also a couple of additional guarantees that all sequence producers (`Observable`s) must honor.

It doesn't matter on which thread they produce elements, but if they generate one element and send it to the observer `observer.on(.Next(nextElement))`, they can't send next element until `observer.on` method has finished execution.

Producers also cannot send terminating `.Completed` or `.Error` in case `.Next` event hasn't finished.

In short, consider this example:

```swift
someObservable
  >- subscribe { (e: Event<Element>) in
      println("Event processing started")
      // processing
      println("Event processing ended")
  }
```

this will always print:

```
Event processing started
Event processing ended
Event processing started
Event processing ended
Event processing started
Event processing ended
```

it can never print:

```
Event processing started
Event processing started
Event processing ended
Event processing ended
```

## Creating your own `Observable` (aka sequence producers)

There is one crucial thing to understand about observables.

**When an observable is created, it doesn't perform any work simply because it has been created.**

It is true that `Observable` can generate elements in many ways. Some of them cause side effects and some of them tap into existing running processes like tapping into mouse events, etc.

**But if you just call a method that returns an `Observable`, no sequence generation is performed, and there are no side effects. `Observable` is just a definition how the sequence is generated and what parameters are used for element generation. Sequence generation starts when `subscribe` method is called.**

E.g. Let's say you have a method with similar prototype:

```swift
func searchWikipedia(searchTerm: String) -> Observable<Results> {}
```

```swift
let searchForMe = searchWikipedia("me")

// no requests are performed, no work is being done, no URL requests were fired

let cancel = searchForMe
  // sequence generation starts now, URL requests are fired
  >- subscribeNext { results in
      println(results)
  }

```

There are a lot of ways how you can create your own `Observable` sequence. Probably the easiest way is using `create` function.

Let's create a function which creates a sequence that returns one element upon subscription. That function is called 'just'.

*This is the actual implementation*

```swift
func myJust<E>(element: E) -> Observable<E> {
    return create { observer in
        sendNext(observer, element)
        sendCompleted(observer)
        return NopDisposable.instance
    }
}

myJust(0)
    >- subscribeNext { n in
      print(n)
    }
```

this will print:

```
0
```

Not bad. So what is the `create` function?

It's just a convenience method that enables you to easily implement `subscribe` method using Swift lambda function. Like `subscribe` method it takes one argument, `observer`, and returns disposable.

So what is the `sendNext` function?

It's just a convenient way of calling `observer.on(.Next(RxBox(element)))`. The same is valid for `sendCompleted(observer)`.

Sequence implemented this way is actually synchronous. It will generate elements and terminate before `subscribe` call returns disposable representing subscription. Because of that it doesn't really matter what disposable it returns, process of generating elements can't be interrupted.

When generating synchronous sequences, the usual disposable to return is singleton instance of `NopDisposable`.

Lets now create an observable that returns elements from an array.

*This is the actual implementation*

```swift
func myFrom<E>(sequence: [E]) -> Observable<E> {
    return create { observer in
        for element in sequence {
            sendNext(observer, element)
        }

        sendCompleted(observer)
        return NopDisposable.instance
    }
}

let stringCounter = myFrom(["first", "second"])

println("Started ----")

// first time
stringCounter
    >- subscribeNext { n in
        println(n)
    }

println("----")

// again
stringCounter
    >- subscribeNext { n in
        println(n)
    }

println("Ended ----")
```

This will print:

```
Started ----
first
second
----
first
second
Ended ----
```

## Creating an `Observable` that performs work

Ok, now something more interesting. Let's create that `interval` operator that was used in previous examples.

*This is equivalent of actual implementation for dispatch queue schedulers*

```swift
func myInterval(interval: NSTimeInterval) -> Observable<Int> {
    return create { observer in
        println("Subscribed")
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue)

        var next = 0

        dispatch_source_set_timer(timer, 0, UInt64(interval * Double(NSEC_PER_SEC)), 0)
        let cancel = AnonymousDisposable {
            println("Disposed")
            dispatch_source_cancel(timer)
        }
        dispatch_source_set_event_handler(timer, {
            if cancel.disposed {
                return
            }
            sendNext(observer, next++)
        })
        dispatch_resume(timer)

        return cancel
    }
}
```

```swift
let counter = myInterval(0.1)

println("Started ----")

let subscription = counter
    >- subscribeNext { n in
       println(n)
    }

NSThread.sleepForTimeInterval(0.5)

subscription.dispose()

println("Ended ----")
```

This will print
```
Started ----
Subscribed
0
1
2
3
4
Disposed
Ended ----
```

What if you would write

```swift
let counter = myInterval(0.1)

println("Started ----")

let subscription1 = counter
    >- subscribeNext { n in
       println("First \(n)")
    }
let subscription2 = counter
    >- subscribeNext { n in
       println("Second \(n)")
    }

NSThread.sleepForTimeInterval(0.5)

subscription1.dispose()

NSThread.sleepForTimeInterval(0.5)

subscription2.dispose()

println("Ended ----")
```

this would print:

```
Started ----
Subscribed
Subscribed
First 0
Second 0
First 1
Second 1
First 2
Second 2
First 3
Second 3
First 4
Second 4
Disposed
Second 5
Second 6
Second 7
Second 8
Second 9
Disposed
Ended ----
```

**Every subscriber upon subscription usually generates it's own separate sequence of elements. Operators are stateless by default. There is vastly more stateless operators then stateful ones.**

## Sharing subscription, refCount and variable operator

But what if you want that multiple observers share events (elements) from only one subscription?

There are two things that need to be defined.

* How to handle past elements that have been received before the new subscriber was interested in observing them (replay latest only, replay all, replay last n)
* How to decide when to fire that shared subscription (refCount, manual or some other algorithm)

The usual choice is a combination of `replay(1) >- refCount`.

```swift
let counter = myInterval(0.1)
    >- replay(1)
    >- refCount

println("Started ----")

let subscription1 = counter
    >- subscribeNext { n in
       println("First \(n)")
    }
let subscription2 = counter
    >- subscribeNext { n in
       println("Second \(n)")
    }

NSThread.sleepForTimeInterval(0.5)

subscription1.dispose()

NSThread.sleepForTimeInterval(0.5)

subscription2.dispose()

println("Ended ----")
```

this will print

```
Started ----
Subscribed
First 0
Second 0
First 1
Second 1
First 2
Second 2
First 3
Second 3
First 4
Second 4
First 5
Second 5
Second 6
Second 7
Second 8
Second 9
Disposed
Ended ----
```

Notice how now there is only one `Subscribed` and `Disposed` event.

This pattern of sharing subscriptions is so common in UI layer that it has it's own operator. Instead of writing `>- replay(1) >- refCount`, you can just write `>- variable`.

Behavior for URL observables is equivalent.

This is how HTTP requests are wrapped in Rx. It's pretty much the same pattern like the `interval` operator.

```swift
extension NSURLSession {
    public func rx_response(request: NSURLRequest) -> Observable<(NSData!, NSURLResponse!)> {
        return create { observer in
            let task = self.dataTaskWithRequest(request) { (data, response, error) in
                if data == nil || response == nil {
                    sendError(observer, error ?? UnknownError)
                }
                else {
                    sendNext(observer, (data, response))
                    sendCompleted(observer)
                }
            }

            task.resume()

            return AnonymousDisposable {
                task.cancel()
            }
        }
    }
}
```

## Operators

There are numerous operators implemented in RxSwift. The complete list can be found [here](API.md).

Marble diagrams for all operators can be found on [ReactiveX.io](http://reactivex.io/)

Almost all operators are demonstrated in [Playgrounds](../Playgrounds).

To use playgrounds please open `Rx.xcworkspace`, build `RxSwift-OSX` scheme and then open playgrounds in `Rx.xcworkspace` tree view.

In case you need an operator, and don't know how to find it there a [decision tree of operators]() http://reactivex.io/documentation/operators.html#tree).

[Supported RxSwift operators](API.md#rxswift-supported-operators) are also grouped by function they perform, so that can also help.

### Custom operators

There are two ways how you can create custom operators.

#### Easy way

All of the internal code uses highly optimized versions of operators, so they aren't the best tutorial material. That's why it's highly encouraged to use standard operators.

Fortunately there is an easier way to create operators. Creating new operators is actually all about creating observables, and previous chapter already describes how to do that.

Lets see how an unoptimized map operator can be implemented.

```swift
func myMap<E, R>(transform: E -> R)(source: Observable<E>) -> Observable<R> {
    return create { observer in

        let subscription = source >- subscribe { e in
                switch e {
                case .Next(let boxedValue):
                    sendNext(observer, transform(boxedValue.value))
                case .Error(let error):
                    sendError(observer, error)
                case .Completed:
                    sendCompleted(observer)
                }
            }

        return subscription
    }
}
```

So now you can use your own map:

```swift
let subscription = myInterval(0.1)
    >- myMap { e in
        return "This is simply \(e)"
    }
    >- subscribeNext { n in
        println(n)
    }
```

and this will print

```
Subscribed
This is simply 0
This is simply 1
This is simply 2
This is simply 3
This is simply 4
This is simply 5
This is simply 6
This is simply 7
This is simply 8
...
```

#### Harder, more performant way

You can perform the same optimizations like we have made and create more performant operators. That usually isn't necessary, but it of course can be done.

Disclaimer: when taking this approach you are also taking a lot more responsibility when creating operators. You will need to make sure that sequence grammar is correct and be responsible of disposing subscriptions.

There are plenty of examples in RxSwift project how to do this. I would suggest talking a look at `map` or `filter` first.

Creating your own custom operators is tricky because you have to manually handle all of the chaos of error handling, asynchronous execution and disposal, but it's not rocket science either.

Every operator in Rx is just a factory for an observable. Returned observable usually contains information about source `Observable` and parameters that are needed to transform it.

In RxSwift code, almost all optimized `Observable`s have a common parent called `Producer`. Returned observable serves as a proxy between subscribers and source observable. It usually performs these things:

* on new subscription creates a sink that performs transformations
* registers that sink as observer to source observable
* on received events proxies transformed events to original observer

### Life happens

So what if it's just too hard to solve some cases with custom operators? You can exit the Rx monad, perform actions in imperative world, and then tunnel results to Rx again using `Subject`s.

This isn't something that should be practiced often, and is a bad code smell, but you can do it.

```swift
  let magicBeings: Observable<MagicBeing> = summonFromMiddleEarth()

  magicBeings
    >- subscribeNext { being in     // exit the Rx monad  
        self.doSomeStateMagic(being)
    }
    >- disposeBag.addDisposable

  //
  //  Mess
  //
  let kitten = globalParty(   // calculate something in messy world
    being,
    UIApplication.delegate.dataSomething.attendees
  )
  sendNext(kittens, kitten)   // send result back to rx
  //
  // Another mess
  //

  let kittens = Variable<Kitten>(firstKitten) // again back in Rx monad

  kittens
    >- map { kitten in
      return kitten.purr()
    }
    // ....
```

Every time you do this, somebody will probably write this code somewhere

```swift
  kittens
    >- subscribeNext { kitten in
      // so something with kitten
    }
    >- disposeBag.addDisposable
```

so please try not to do this.

## Playgrounds

If you are unsure how exactly some of the operators work, [playgrounds](../Playgrounds) contain almost all of the operators already prepared with small examples that illustrate their behavior.

**To use playgrounds please open Rx.xcworkspace, build RxSwift-OSX scheme and then open playgrounds in Rx.xcworkspace tree view.**

**To view the results of the examples in the playgrounds, please open the `Assistant Editor`. You can open `Assistant Editor` by clicking on `View > Assistant Editor > Show Assistant Editor`**

## Error handling

The are two error mechanisms.

### Anynchronous error handling mechanism in observables

Error handling is pretty straightforward. If one sequence terminates with error, then all of the dependent sequences will terminate with error. It's usual short circuit logic.

You can recover from failure of observable by using `catch` operator. There are various overloads that enable you to specify recovery in great detail.

There is also `retry` operator that enables retries in case of errored sequence.

### Synchronous error handling

Unfortunately Swift doesn't have a concept of exceptions or some kind of built in error monad so this project introduces `RxResult` enum.
It is Swift port of Scala [`Try`](http://www.scala-lang.org/api/2.10.2/index.html#scala.util.Try) type. It is also similar to Haskell [`Either`](https://hackage.haskell.org/package/category-extras-0.52.0/docs/Control-Monad-Either.html) monad.

**This will be replaced in Swift 2.0 with try/throws**

```swift
public enum RxResult<ResultType> {
    case Success(ResultType)
    case Error(ErrorType)
}
```

To enable writing more readable code, a few `Result` operators are introduced

```swift
result1.flatMap { okValue in        // success handling block
    // executed on success
    return ?
}.recoverWith { error in            // error handling block
    //  executed on error
    return ?
}
```

### Error handling and function names

For every group of transforming functions there are versions with and without "OrDie" suffix.

**This will change in 2.0 version and map will have two overloads, with and without `throws`.**

e.g.

```swift
public func mapOrDie<E, R>
    (selector: E -> RxResult<R>)
    -> (Observable<E> -> Observable<R>) {
    return { source in
        return selectOrDie(selector)(source)
    }
}

public func map<E, R>
    (selector: E -> R)
        -> (Observable<E> -> Observable<R>) {
    return { source in
        return select(selector)(source)
    }
}
```

Returning an error from a selector will cause entire graph of dependent sequence transformers to "die" and fail with error. Dying implies that it will release all of its resources and never produce another sequence value. This is usually not an obvious effect.

If there is some `UITextField` bound to a observable sequence that fails with error or completes, screen won't be updated ever again.

To make those situations more obvious, RxCocoa debug build will throw an exception in case some sequence that is bound to UI control terminates with an error.

Using functions without "OrDie" suffix is usually a more safe option.

There is also the `catch` operator for easier error handling.

## Debugging Compile Errors

When writing elegant RxSwift/RxCocoa code, you are probably relying heavily on compiler to deduce types of `Observable`s. This is one of the reasons why Swift is awesome, but it can also be frustrating sometimes.

```swift
images = word
    >- filter { $0.rangeOfString("important") != nil }
    >- flatMap { word in
        return self.api.loadFlickrFeed("karate")
            >- catch { error in
                return just(JSON(1))
            }
      }
```

If compiler reports that there is an error somewhere in this expression, I would suggest first annotating return types.

```swift
images = word
    >- filter { s -> Bool in s.rangeOfString("important") != nil }
    >- flatMap { word -> Observable<JSON> in
        return self.api.loadFlickrFeed("karate")
            >- catch { error -> Observable<JSON> in
                return just(JSON(1))
            }
      }
```

If that doesn't work, you can continue adding more type annotations until you've localized the error.

```swift
images = word
    >- filter { (s: String) -> Bool in s.rangeOfString("important") != nil }
    >- flatMap { (word: String) -> Observable<JSON> in
        return self.api.loadFlickrFeed("karate")
            >- catch { (error: NSError) -> Observable<JSON> in
                return just(JSON(1))
            }
      }
```

**I would suggest first annotating return types and arguments of closures.**

Usually after you have fixed the error, you can remove the type annotations to clean up your code again.

## Debugging

Using debugger alone is useful, but you can also use `>- debug`. `debug` operator will print out all events to standard output and you can add also label those events.

`debug` acts like a probe. Here is an example of using it:

```swift
let subscription = myInterval(0.1)
    >- debug("my probe")
    >- map { e in
        return "This is simply \(e)"
    }
    >- subscribeNext { n in
        println(n)
    }

NSThread.sleepForTimeInterval(0.5)

subscription.dispose()
```

will print

```
[my probe] subscribed
Subscribed
[my probe] -> Event Next(Box(0))
This is simply 0
[my probe] -> Event Next(Box(1))
This is simply 1
[my probe] -> Event Next(Box(2))
This is simply 2
[my probe] -> Event Next(Box(3))
This is simply 3
[my probe] -> Event Next(Box(4))
This is simply 4
[my probe] dispose
Disposed
```

You can also use `subscribe` instead of `subscribeNext`

```swift
NSURLSession.sharedSession().rx_JSON(request)
   >- map { json in
       return parse()
   }
   >- subscribe { n in      // this subscribes on all events including error and completed
       println(n)
   }
```

## Debugging memory leaks

In debug mode Rx tracks all allocated resources in a global variable `resourceCount`.

**Printing `Rx.resourceCount` after pushing a view controller onto navigation stack, using it, and then popping back is usually the best way to detect and debug resource leaks.**

As a sanity check, you can just do a `println` in your view controller `deinit` method.

The code would look something like this.

```swift
class ViewController: UIViewController {
#if TRACE_RESOURCES
    private let startResourceCount = RxSwift.resourceCount
#endif

    override func viewDidLoad() {
      super.viewDidLoad()
#if TRACE_RESOURCES
        println("Number of start resources = \(resourceCount)")
#endif
    }

    deinit {
#if TRACE_RESOURCES
        println("View controller disposed with \(resourceCount) resources")

        var numberOfResourcesThatShouldRemain = startResourceCount
        let time = dispatch_time(DISPATCH_TIME_NOW, Int64(0.1 * Double(NSEC_PER_SEC)))
        dispatch_after(time, dispatch_get_main_queue(), { () -> Void in
            println("Resource count after dealloc \(RxSwift.resourceCount), difference \(RxSwift.resourceCount - numberOfResourcesThatShouldRemain)")
        })
#endif
    }
}
```

The reason why you should use a small delay is because sometimes it takes a small amount of time for scheduled entities to release their memory.

## Variables

`Variable`s represent some observable state. `Variable` without containing value can't exist because initializer requires initial value.

Variable is a [`Subject`](http://reactivex.io/documentation/subject.html). More specifically it is a `BehaviorSubject`.  Because `BehaviorSubject` is aliased as `Variable` for convenience.

`Variable` is both an `ObserverType` and `Observable`.

That means that you can send values to variables using `sendNext` and it will broadcast element to all subscribers.

It will also broadcast it's current value immediately on subscription.

```swift
let variable = Variable(0)

println("Before first subscription ---")

variable
    >- subscribeNext { n in
        println("First \(n)")
    }

println("Before send 1")

sendNext(variable, 1)

println("Before second subscription ---")

variable
    >- subscribeNext { n in
        println("Second \(n)")
    }

sendNext(variable, 2)

println("End ---")
```

will print

```
Before first subscription ---
First 0
Before send 1
First 1
Before second subscription ---
Second 1
First 2
Second 2
End ---
```

There is also `>- variable` operator. `>- variable` operator is already described [here](#sharing-subscription-refcount-and-variable-operator).

So why are they both called variable?

For one, they both have internal state that all subscribers share.
When they contain value (and `Variable` always contains it), they broadcast it immediately to subscribers.

The difference is that `Variable` enables you to manually choose elements of a sequence by using `sendNext`, and you can think of `>- variable` as a kind calculated "variable".

## KVO

KVO is an Objective-C mechanism. That means that it wasn't built with type safety in mind. This project tries to solve some of the problems.

There are two built in ways this library supports KVO.

```swift
// KVO
extension NSObject {
    public func rx_observe<Element>(keyPath: String, retainSelf: Bool = true) -> Observable<Element?> {}
}

#if !DISABLE_SWIZZLING
// KVO
extension NSObject {
    public func rx_observeWeakly<Element>(keyPath: String) -> Observable<Element?> {}
}
#endif
```

**If Swift compiler doesn't have a way to deduce observed type (return Observable type), it will report error about function not existing.**

Here are some ways you can give him hints about observed type:

```swift
view.rx_observe("frame") as Observable<CGRect?>
```

or

```swift
view.rx_observe("frame")
    >- map { (rect: CGRect?) in
        //
    }
```

### `rx_observe`

`rx_observe` is more performant because it's just a simple wrapper around KVO mechanism, but it has more limited usage scenarios

* it can be used to observe paths starting from `self` or from ancestors in ownership graph (`retainSelf = false`)
* it can be used to observe paths starting from descendants in ownership graph (`retainSelf = true`)
* the paths have to consist only of `strong` properties, otherwise you are risking crashing the system by not unregistering KVO observer before dealloc.

E.g.

```swift
self.rx_observe("view.frame", retainSelf = false) as Observable<CGRect?>
```

### `rx_observeWeakly`

`rx_observeWeakly` has somewhat worse performance because it has to handle object deallocation in case of weak references.

It can be used in all cases where `rx_observe` can be used and additionally

* because it won't retain observed target, it can be used to observe arbitrary object graph whose ownership relation is unknown
* it can be used to observe `weak` properties

E.g.

```swift
someSuspiciousViewController.rx_observeWeakly("behavingOk") as Observable<Bool?>
```

### Observing structs

KVO is an Objective-C mechanism so it relies heavily on `NSValue`. RxCocoa has additional specializations for `CGRect`, `CGSize` and `CGPoint` that make it convenient to observe those types.

When observing some other structures it is necessary to extract those structures from `NSValue` manually, or creating your own observable sequence specializations.

[Here](../RxCocoa/RxCocoa/Common/Observables/NSObject+Rx+CoreGraphics.swift) are examples how to correctly extract structures from `NSValue`.

## UI layer tips

There are certain things that your `Observable`s need to satisfy in the UI layer when binding to UIKit controls.

### Threading

`Observable`s need to send values on `MainScheduler`(UIThread). That's just a normal UIKit/Cocoa requirement.

It is usually a good idea for you APIs to return results on `MainScheduler`. In case you try to bind something to UI from background thread, in **Debug** build RxCocoa will usually throw an exception to inform you of that.

To fix this you need to add `>- observeOn(MainScheduler.sharedInstance)`.

**NSURLSession extensions don't return result on `MainScheduler` by default.**

### Errors

You can't bind failure to UIKit controls because that is undefined behavior.

If you don't know if `Observable` can fail, you can ensure it can't fail using `>-catch(valueThatIsReturnedWhenErrorHappens)`

### Sharing subscription

You usually want to share subscription in the UI layer. You don't want to make separate HTTP calls to bind the same data to multiple UI elements.

Let's say you have something like this:

```swift
let searchResults = searchText
    >- throttle(0.3, $.mainScheduler)
    >- distinctUntilChanged
    >- map { query in
        API.getSearchResults(query)
            >- retry(3)
            >- startWith([]) // clears results on new search term
            >- catch([])
    }
    >- switchLatest
    >- variable              // <- notice the variable
```

What you usually want is to share search results once calculated. That is what `>- variable` means.

**It is usually a good rule of thumb in the UI layer to add `>- variable` at the end of transformation chain because you really want to share calculated results. You don't want to fire separate HTTP connections when binding `searchResults` to multiple UI elements.**

*Additional information about `>- variable` can be found [here](#sharing-subscription-refcount-and-variable-operator)*

## Making HTTP requests

Making http requests is one of the first things people try.

You first need to build `NSURLRequest` object that represents the work that needs to be done.

Request determines is it a GET request, or a POST request, what is the request body, query parameters ...

This is how you can create a simple GET request

```swift
let request = NSURLRequest(URL: NSURL(string: "http://en.wikipedia.org/w/api.php?action=parse&page=Pizza&format=json")!)
```

If you want to just execute that request outside of composition with other observables, this is what needs to be done.

```swift
let responseJSON = NSURLSession.sharedSession().rx_JSON(request)

// no requests will be performed up to this point
// `responseJSON` is just a description how to fetch the response

let cancelRequest = responseJSON
    // this will fire the request
    >- subscribeNext { json in
        println(json)
    }

NSThread.sleepForTimeInterval(3)

// if you want to cancel request after 3 seconds have passed just call
cancelRequest.dispose()

```

**NSURLSession extensions don't return result on `MainScheduler` by default.**

In case you want a more low level access to response, you can use:

```swift
NSURLSession.sharedSession().rx_response(myNSURLRequest)
    >- debug("my request") // this will print out information to console
    >- flatMap { (data: NSData!, response: NSURLResponse!) -> Observable<String> in
        if let response = response as? NSHTTPURLResponse {
            if 200 ..< 300 ~= response.statusCode {
                return just(transform(data))
            }
            else {
                return failWith(yourNSError)
            }
        }
        else {
            rxFatalError("response = nil")
            return failWith(yourNSError)
        }
    }
    >- subscribe { event in
        println(event) // if error happened, this will also print out error to console
    }
```
### Logging HTTP traffic

In debug mode RxCocoa will log all HTTP request to console by default. In case you want to change that behavior, please set `Logging.URLRequests` filter.

```swift
// read your own configuration
public struct Logging {
    public typealias LogURLRequest = (NSURLRequest) -> Bool

    public static var URLRequests: LogURLRequest =  { _ in
    #if DEBUG
        return true
    #else
        return false
    #endif
    }
}
```

## RxDataSourceStarterKit

... is a set of classes that implement fully functional reactive data sources for `UITableView`s and `UICollectionView`s.

Source code, more information and rationale why these classes are separated into their directory can be found [here](../RxDataSourceStarterKit).

Using them should come down to just importing all of the files into your project.

Fully functional demonstration how to use them is included in the [RxExample](../RxExample) project.
