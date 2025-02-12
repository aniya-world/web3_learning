pragma solidity >=0.4.25 <0.9.0; 
// https://github.com/RemoteCodeCamp/openWeb3/blob/main/03.%E4%BD%BF%E7%94%A8Solidity%20%E7%BC%96%E5%86%99%20Ethereum%E6%99%BA%E8%83%BD%E5%90%88%E5%90%8C.md
// 用于管理运输状态
contract Shipping { 
    // Our predefined values for shipping listed as enums 
    enum ShippingStatus { Pending, Shipped, Delivered } 

    // Save enum ShippingStatus in variable status 
    ShippingStatus private status; 

    // Event to launch when package has arrived 包裹到达时触发
    event LogNewAlert(string description); 

    // This initializes our contract state (sets enum to Pending once the program starts) 
    constructor(){ status = ShippingStatus.Pending; } 

    // Function to change to Shipped  更改状态为 Shipped
    function Shipped() public {
        status = ShippingStatus.Shipped; 
        emit LogNewAlert("Your package has been shipped"); 
    } 

    // Function to change to Delivered  更改状态为 Delivered
    function Delivered() public { 
        status = ShippingStatus.Delivered; 
        emit LogNewAlert("Your package has arrived"); 
    } 

    // Function to get the status of the shipping 获取当前状态的字符串表示
    function getStatus(ShippingStatus _status) internal pure returns (string memory statusText) { 
        // Check the current status and return the correct name
         if (ShippingStatus.Pending == _status) return "Pending"; 
         if (ShippingStatus.Shipped == _status) return "Shipped"; 
         if (ShippingStatus.Delivered == _status) return "Delivered"; 
    } 

    // Get status of your shipped item 获取已发货物品的状态
    function Status() public view returns (string memory) { 
        ShippingStatus _status = status; 
        return getStatus(_status); 
    }

}