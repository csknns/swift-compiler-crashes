protocol P {}

extension P {
    func defaultImplementation() {}
}

class C : P {
    
    func customImplementation() {
        P.defaultImplementation(self)()
    }
}

