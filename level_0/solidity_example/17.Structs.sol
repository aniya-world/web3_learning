// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Todos {
    /*在 Solidity 中，
    struct（结构体）是一种用户定义的数据类型，用于将多个相关的变量组合在一起。
    结构体允许开发者创建复杂的数据类型，以便更好地组织和管理数据。
    它们类似于其他编程语言中的结构体或类，但没有方法或行为，只是用于存储数据。
    1. 定义和使用
    要定义一个结构体，你可以使用 struct 关键字。结构体可以包含不同类型的变量，包括基本数据类型（如 uint, string, address 等）和其他结构体。

    这里定义了一个名为 Todo 的结构体，它包含两个字段：
    text：一个字符串，用于存储待办事项的描述。
    completed：一个布尔值，用于指示待办事项是否已完成
*/
    struct Todo {
        string text;
        bool completed;
    }

    // todos 是一个公共数组，用于存储多个 Todo 结构体的实例。由于它是公共的，Solidity 会自动生成一个 getter 函数，使得外部可以访问这个数组。
    Todo[] public todos;
    /*
    在 Solidity 中，calldata 是一种数据位置（data location），用于指定函数参数的存储方式。它主要用于函数的输入参数，尤其是在外部函数（external）中。以下是对 calldata 的详细解释：
    1. 数据位置
    Solidity 中有三种主要的数据位置：
    storage：用于存储合约的状态变量，数据存储在区块链上，生命周期与合约相同。
    memory：用于临时存储数据，数据存储在内存中，生命周期仅在当前函数调用期间有效。
    calldata：用于外部函数的参数，数据存储在调用者的内存中，不能被修改，生命周期与函数调用相同。
    
    2. calldata 的特点
    只读：calldata 中的数据是只读的，不能被修改。这意味着在函数内部不能改变 calldata 参数的值。
    节省 gas：使用 calldata 可以节省 gas，因为它不需要在内存中复制数据。对于大型数据结构（如字符串或数组），使用 calldata 可以更高效。
    外部函数：calldata 只能用于外部函数的参数，不能用于内部函数或合约的状态变量。
    */

    // create 函数接受一个字符串参数 _text，用于创建新的待办事项。
    function create(string calldata _text) public {
        // 3 ways to initialize a struct
        // 1. 调用结构体像函数一样：- calling it like a function  ,直接使用构造函数的方式来创建 Todo 实例，并将其推入 todos 数组
        todos.push(Todo(_text, false));

        // 2.使用键值对的方式来初始化结构体的字段。这种方式在字段较多时更具可读性。 key value mapping 
        todos.push(Todo({text: _text, completed: false}) );

        // 3.初始化空结构体并更新 initialize an empty struct and then update it
        Todo memory todo;
        todo.text = _text;
        // todo.completed initialized to false

        todos.push(todo);
    }



    // Solidity automatically created a getter for 'todos' so
    // you don't actually need this function.
    // 这个函数用于获取指定索引 _index 的待办事项的文本和完成状态。
    function get(uint256 _index)
        public
        view
        returns (string memory text, bool completed)
    {
        // 使用 storage 关键字来引用 todos 数组中的结构体实例，这样可以直接修改它的值,（如果需要的话） 之后返回
        Todo storage todo = todos[_index];
        return (todo.text, todo.completed);
    }

    // update text
    function updateText(uint256 _index, string calldata _text) public {
        Todo storage todo = todos[_index];
        todo.text = _text;
    }

    // update completed
    function toggleCompleted(uint256 _index) public {
        Todo storage todo = todos[_index];
        todo.completed = !todo.completed;
    }


    // Solidity 中的 Todo 结构体数组确实可以类比为 Python 中的列表和字典的组合
    /* the python code is like:
	    todos = [
		    {"text": "Buy groceries", "completed": False},
		    {"text": "Walk the dog", "completed": True},
		]
	*/
}
 