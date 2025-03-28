// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// This is saved 'StructDeclaration.sol'

struct Todo {
    string text;
    bool completed;
}


// File that imports the struct above
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./StructDeclaration.sol";

contract Todos {
    // An array of 'Todo' structs
    Todo[] public todos;
}