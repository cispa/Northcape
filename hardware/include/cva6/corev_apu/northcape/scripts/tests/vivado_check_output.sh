#!/bin/sh
check_test_result(){
    LOGFILE=$1
    # TODO Vivado appears to just completely ignore $fatal
    tail -10 $LOGFILE | grep "Test error!" && echo "Test error - check log!" && touch .test_fail
    # TODO the normal mechanism does not work for timeouts...
    grep "PH_TIMEOUT" $LOGFILE && echo "Test timeout - check log!" && touch .test_fail
    echo "Test OK!"
}
