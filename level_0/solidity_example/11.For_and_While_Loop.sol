// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Loop {
    // pure这里不需要访问合约Loop的状态变量，加上，避免编辑器报错
    function loop() public pure returns (uint256) {

        for (uint256 i=0; i<10; i++) {
            if (i==3) {
                continue;
            }
            if (i==5) {
                break;
            }
        }

        // 这里尽量初始化一下
        uint256 j=0;
        while (j<10) {
            j++;
        }
        return j;

    }
}