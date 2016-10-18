<p align="left"><img src="https://cloud.githubusercontent.com/assets/1567433/19490843/61cd2460-9579-11e6-9269-6cdebdf2a1cb.png" height="100"/>

<p align="left">
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
<a href="https://travis-ci.org/kean/Pill"><img src="https://img.shields.io/travis/kean/Pill/master.svg"></a>
</p>

Micro Promise under 100 sloc. Supports chaining, recovery, bubbles-up errors. Covered by Promise/A+ [test suite](https://github.com/promises-aplus/promises-tests).

## Requirements

- iOS 9.0 / watchOS 2.0 / OS X 10.11 / tvOS 9.0
- Xcode 8, Swift 3

## Usage

```swift
cache.data(for: request)
    .recover { error in loadData(with: request) }
    .then { cache.setData($0, for: request) }
    .then { process(data: $0) }
    .catch { error in print("catched \(error)") }
```

#### Synchronous Inspection

```swift
// Retrieve the fulfillment value or the rejection reason
promise.resolution?.value
promise.resolution?.error
```

## License

Pill is available under the MIT license. See the LICENSE file for more info.
