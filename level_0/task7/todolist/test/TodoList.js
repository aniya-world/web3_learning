const hre = require("hardhat");

async function main() {
  // 获取合约地址
  const contractAddress = "0x7F98455Aaaa414fC4d8c83Ec635E5488614eC1E9";

  // 获取合约实例
  const todoList = await hre.ethers.getContractAt("TodoList", contractAddress);

  // 获取签名者
  const [signer] = await hre.ethers.getSigners();

  try {
    // 获取当前任务数量
    const taskCount = await todoList.taskCount();
    console.log("当前任务数量:", taskCount.toString());

    // 创建新任务
    console.log("创建新任务...");
    const createTx = await todoList.createTask("完成智能合约作业");
    await createTx.wait();
    console.log("任务创建成功！");

    // 获取新创建的任务
    const newTask = await todoList.tasks(taskCount + 1n);
    console.log("新任务详情:", {
      id: newTask.id.toString(),
      taskname: newTask.taskname,
      status: newTask.status
    });

    // 切换任务状态
    console.log("切换任务状态...");
    const toggleTx = await todoList.toggleStatus(taskCount + 1n);
    await toggleTx.wait();
    console.log("任务状态已更新！");

    // 获取更新后的任务状态
    const updatedTask = await todoList.tasks(taskCount + 1n);
    console.log("更新后的任务状态:", updatedTask.status);

  } catch (error) {
    console.error("错误:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });