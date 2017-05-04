module timer;

import core.time;

struct Timer {
    nothrow @safe :

    private MonoTime time;

    /* Time elapsed (in milliseconds) since timer creation or since last call to reset */
    @property long elapsedTime() {
        Duration timeElapsed = MonoTime.currTime - time;

        return timeElapsed.total!"msecs";
    }

    @property Timer reset() {
        time = MonoTime.currTime;
        return this;
    }
}
