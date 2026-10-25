class Counter {
    int64 double(int64 value) {
        int64 doubled = value * 2
        return(doubled)
    }
}

start {
    int64 counter = 21
    counter = Counter().double(counter)
    print(counter)
}
