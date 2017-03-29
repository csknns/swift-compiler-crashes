public struct T<Specific> {
    public typealias Closure = (Specific) -> Void
}

let closure: T.Closure = { (input: String) in
    print("\(input)")
}
