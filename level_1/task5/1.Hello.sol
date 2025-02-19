pragma solidity ^0.8.17;

contract Hello {
    string storeMsg;

    function set (string memory text) public {
        storeMsg = text;
    }

    function get () public view returns (string memory) {
        return storeMsg;
    }
}