// SPDX-License-Identifier: MIT 
pragma solidity >=0.4.22 <0.9.0; 
contract TodoList { 
    uint public taskCount = 0;
    struct Task { 
        uint id; 
        string taskname; 
        bool status; 
    } 
    mapping(uint => Task) public tasks; //声明了一个映射 tasks，将无符号整数（任务 ID）映射到 Task 结构体。这使得可以通过任务 ID 来访问相应的任务
    //  当创建新任务时会发出该事件，包含任务的 ID、名称和状
    event TaskCreated(  
        uint id, 
        string taskname, 
        bool status 
    ); 
    event TaskStatus( 
        uint id, 
        bool status 
    ); 
    constructor() { 
        createTask("Todo List Tutorial"); //在合约部署时自动调用。它调用 createTask 函数创建一个初始任务，名称为 "Todo List Tutorial"
    } 
    function createTask(string memory _taskname) public { 
        taskCount ++; 
        tasks[taskCount] = Task(taskCount, _taskname, false); 
        emit TaskCreated(taskCount, _taskname, false); // 发出 TaskCreated 事件，记录新任务的 ID、名称和状态
    }
    function toggleStatus(uint _id) public { 
        Task memory _task = tasks[_id];
        _task.status = !_task.status;  //切换 _task 的状态（如果是 true 则变为 false，反之亦然）。
        tasks[_id] = _task; // 将更新后的任务存回 tasks 映射中
        emit TaskStatus(_id, _task.status);  // 发出 TaskStatus 事件，记录任务的 ID 和新的状态
    } 
}