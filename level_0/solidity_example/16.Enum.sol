// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Enum {

    // enum 是一种简单的类型，用于定义一组常量，没有方法或属性。它的主要目的是提供可读性和类型安全。
        // 例如，Status.Pending、Status.Shipped 等是 Status 枚举的值。
    // enum 不支持继承或扩展。它是一个简单的类型定义。
    enum Status {
        Pending,
        Shipped,
        Accepted,
        Rejected,
        Canceled
    }
    // Default value is the first element listed in, in this case "Pending"
    Status public status;
    // Returns uint
    // Pending  - 0
    // Shipped  - 1
    // Accepted - 2
    // Rejected - 3
    // Canceled - 4
    function get() public view returns (Status) {
        return status;
    }

    // Update status by passing uint into input
    function set(Status _status) public {
        // set n is n
        status = _status;
    }

    function cancel() public {
        // status = Status.Canceled; 不应该写为status.Canceled吗？
        // 在 Solidity 中，访问枚举的值时，应该使用枚举类型的名称作为前缀。
        // 因此，正确的写法是 status = Status.Canceled;，而不是 status.Canceled
        // 如果你写成 status.Canceled，编译器会报错，因为 status 是一个变量，而不是枚举类型，不能直接访问枚举的值
        status = Status.Canceled;
    }

    // delete resets the enum to its first value, 0
    function reset() public {
        delete status;
    }

}
 