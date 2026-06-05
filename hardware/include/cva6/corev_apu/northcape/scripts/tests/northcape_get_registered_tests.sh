#!/bin/sh

get_registered_tests () {
    TEST_LIST=$(sed -n '/========= Test List Start =========/,/========= Test List End =========/{/========= Test List Start =========/b;/========= Test List End =========/b;p}' $1 | grep "test_")
    echo "$TEST_LIST"
}
