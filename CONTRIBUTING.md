# How to contribute

Contributing to swift-compiler-crashes is really easy – you only need to submit one file in your pull request; the crash case.

The crash cases are named according to the following pattern:

````
    crashes/[crash-case-number]-[swiftc-function-where-there-crash-occurs-in-hyphenated-lowercase].swift
````

For example, the crash case 226 is triggered in function `swift::Lowering::SILGenFunction::emitCurryThunk(…)` and is thus named `crashes/00226-swift-lowering-silgenfunction-emitcurrythunk.swift`.

## Step-by-step guide

### 1. Find the currently highest crash case number in use

````
    $ ls -1 crashes/ crashes-fuzzing/ crashes-duplicates/ fixed/ | egrep '^[0-9]{5}-.*\.swift' | sort -n | tail -1
    22721-substituteinputsugarargumenttype.swift
````

The highest crash case number in this example is 22721, so we'll use the next available slot; 22722.

### 2. Find out in which Swift compiler function your crash case is triggered

````
    $ swiftc crash.swift 2>&1 | egrep '[0-9]x[0-9a-f]{16}' | grep swift:: | head -1
    4  swift                    0x000000010d83c4ef swift::irgen::ProtocolInfo::getConformance(swift::irgen::IRGenModule&, swift::CanType, swift::irgen::TypeInfo const&, swift::ProtocolDecl*, swift::ProtocolConformance const&) const + 207
````

The compiler crashes in `swift::irgen::ProtocolInfo::getConformance`, so we'll use the hyphenated lower-case version `swift-irgen-protocolinfo-getconformance`.

### 3. Name your crash case, commit, push and create a pull request

````
    $ mv crash.swift crashes/22722-swift-irgen-protocolinfo-getconformance.swift
    $ git add crashes/22722-swift-irgen-protocolinfo-getconformance.swift
    $ git commit
    $ git push
    $ say "Don't forget to submit a pull request on GitHub. Thanks."
````

If the crash case causes a compiler hang and not an explicit crash, use a `.timeout.swift` suffix, rather than the plain `.swift` suffix. This will tell the test suite runner that this is a compiler hang bug. The test suite runner will attempt to compile it with a [5 second timeout](https://github.com/practicalswift/swift-compiler-crashes/blob/9a23124d8fb34cbc2622bfc3a5b5fe9c31006ec0/test.sh#L125-L128).

By contributing code to this repository you are dual-licensing your contribution under the following two licenses:
* The Apache License
* The MIT License

Thanks!
