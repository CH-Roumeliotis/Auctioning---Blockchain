const SmartAuctioning = artifacts.require("SmartAuctioning");

module.exports = function (deployer) {
  deployer.deploy(SmartAuctioning);
};
