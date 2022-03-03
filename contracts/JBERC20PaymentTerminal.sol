// SPDX-License-Identifier: MIT
/* solhint-disable comprehensive-interface*/
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// Inheritance
import './JBPaymentTerminal.sol';

contract JBERC20PaymentTerminal is JBPaymentTerminal {
  constructor(
    IERC20 _token,
    uint256 _currency,
    IJBOperatorStore _operatorStore,
    IJBProjects _projects,
    IJBDirectory _directory,
    IJBSplitsStore _splitsStore,
    JBPaymentTerminalStore _store,
    address _owner
  )
    JBPaymentTerminal(
      address(_token),
      _currency,
      _operatorStore,
      _projects,
      _directory,
      _splitsStore,
      _store,
      _owner
    )
  {}

  function _transferFrom(
    address _from,
    address payable _to,
    uint256 _amount
  ) internal override {
    IERC20(token).transferFrom(_from, _to, _amount);
  }

  function _beforeTransferTo(address _to, uint256 _amount) internal override {
    IERC20(token).approve(_to, _amount);
  }
}
