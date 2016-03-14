
func f(value: Any) {
}

struct A {
}

Mirror(reflecting: A()).children.forEach(f)
