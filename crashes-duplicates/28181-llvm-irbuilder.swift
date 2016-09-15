struct A {
    func a() -> String {
        return ""
    }
}
func b() {
    guard let c = A.a as? String else {
        return
    }
}
