// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ArrayReplaceFromEnd {

    uint256[] public arr = [1,2,3];

    function remove(uint256 index) public{
        // Remove array element by copying last element into to the place to remove
        arr[index] = arr[arr.length - 1];
        // Remove the last element
        arr.pop();
    }


    function test() external {
        arr = [1, 2, 3, 4];
        remove(1);
        // [1, 4, 3]
        // arr[1] = arr[3], move "4" to "2" -> [1,4,3,4] -> pop -> [1,4,3]
        assert(arr[0] == 1);
        assert(arr[1] == 4);
        assert(arr[2] == 3);
        assert(arr.length == 3);

        // [1,4,3].remove(2)
        remove(2);
        // -> [1,4,3] -> pop -> [1,4]
        assert(arr.length == 2);
        assert(arr[0] == 1);
        assert(arr[1] == 4);

    }

}
 