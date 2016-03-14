// Distributed under the terms of the MIT license
// Submitted by https://github.com/deville (Andrii Chernenko)

func f(value: Any) {
}

struct A {
}

Mirror(reflecting: A()).children.forEach(f)
