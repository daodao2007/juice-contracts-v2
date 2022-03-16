// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@paulrberg/contracts/math/PRBMath.sol';
import './helpers/TestBaseWorkflow.sol';
import './mock/MockPriceFeed.sol';

contract TestMultipleTerminals is TestBaseWorkflow {

  JBController controller;
  JBProjectMetadata _projectMetadata;
  JBFundingCycleData _data;
  JBFundingCycleMetadata _metadata;
  JBGroupedSplits[] _groupedSplits;
  JBFundAccessConstraints[] _fundAccessConstraints;

  IJBPaymentTerminal[] _terminals;
  JB18DecimalERC20PaymentTerminal ERC20terminal;
  JBETHPaymentTerminal ETHterminal;

  JBTokenStore _tokenStore;
  address _projectOwner;

  uint256 FAKE_PRICE = 10;
  uint256 WEIGHT = 1000 * 10**18;
  uint256 projectId;

  function setUp() public override {
    super.setUp();

    _projectOwner = multisig();

    _tokenStore = jbTokenStore();

    controller = jbController();

    _projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    _data = JBFundingCycleData({
      duration: 14,
      weight: WEIGHT,
      discountRate: 450000000,
      ballot: IJBFundingCycleBallot(address(0))
    });

    _metadata = JBFundingCycleMetadata({
      reservedRate: 5000,
      redemptionRate: 5000,
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseMint: false,
      pauseBurn: false,
      allowChangeToken: false,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      useLocalBalanceForRedemptions: false,
      useDataSourceForPay: false,
      useDataSourceForRedeem: false,
      dataSource: IJBFundingCycleDataSource(address(0))
    });

    ERC20terminal = new JB18DecimalERC20PaymentTerminal(
      jbToken(),
      jbLibraries().USD(), // currency
      jbLibraries().ETH(), // base weight currency
      1, // JBSplitsGroupe
      jbOperatorStore(),
      jbProjects(),
      jbDirectory(),
      jbSplitsStore(),
      jbPrices(),
      jbPaymentTerminalStore(),
      multisig()
    );
    evm.label(address(ERC20terminal), 'JBERC20PaymentTerminalUSD');

    ETHterminal = jbETHPaymentTerminal();

    _fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: ERC20terminal,
        distributionLimit: 10*10**18,
        overflowAllowance: 5*10**18,
        distributionLimitCurrency: jbLibraries().USD(),
        overflowAllowanceCurrency: jbLibraries().USD()
      })
    );

    _fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: ETHterminal,
        distributionLimit: 10*10**18,
        overflowAllowance: 5*10**18,
        distributionLimitCurrency: jbLibraries().ETH(),
        overflowAllowanceCurrency: jbLibraries().ETH()
      })
    );

    _terminals.push(ERC20terminal);
    _terminals.push(ETHterminal);

    projectId = controller.launchProjectFor(
      _projectOwner,
      _projectMetadata,
      _data,
      _metadata,
      block.timestamp,
      _groupedSplits,
      _fundAccessConstraints,
      _terminals
    );

    evm.startPrank(_projectOwner); // If evm.prank(), pranking only jbLib call...

    MockPriceFeed _priceFeed = new MockPriceFeed(FAKE_PRICE);
    evm.label(address(_priceFeed), 'MockPrice Feed');

    jbPrices().addFeedFor(
      jbLibraries().USD(), // currency
      jbLibraries().ETH(), // base weight currency
      _priceFeed
    );

    jbPrices().addFeedFor(
      jbLibraries().ETH(), // currency
      jbLibraries().USD(), // base weight currency
      _priceFeed
    );

    evm.stopPrank();
  }

  function testMultipleTerminal() public {
    // Send some token to the caller, so he can play
    address caller = msg.sender;
    evm.label(caller, 'caller');
    evm.prank(_projectOwner);
    jbToken().transfer(caller, 20*10**18);

    // ---- Pay in token ----
    evm.prank(caller); // back to regular msg.sender (bug?)
    jbToken().approve(address(ERC20terminal), 20*10**18);
    evm.prank(caller); // back to regular msg.sender (bug?)
    ERC20terminal.pay(20*10**18, projectId, msg.sender, 0, false, 'Forge test', new bytes(0));

    // verify: beneficiary should have a balance of JBTokens (divided by 2 -> reserved rate = 50%)
    // price feed will return FAKE_PRICE*18 (for curr usd/base eth); since it's an 18 decimal terminal (ie calling getPrice(18) )
    uint256 _userTokenBalance = PRBMath.mulDiv( 20*10**18, WEIGHT, 36*FAKE_PRICE);
    assertEq(_tokenStore.balanceOf(msg.sender, projectId), _userTokenBalance);

    // verify: balance in terminal should be up to date
    assertEq(jbPaymentTerminalStore().balanceOf(ERC20terminal, projectId), 20*10**18);


    // ---- Pay in ETH ----
    address beneficiaryTwo = address(696969);
    ETHterminal.pay{value: 20 ether}(20 ether, projectId, beneficiaryTwo, 0, false, 'Forge test', new bytes(0)); // funding target met and 10 ETH are now in the overflow

     // verify: beneficiary should have a balance of JBTokens (divided by 2 -> reserved rate = 50%)
    uint256 _userEthBalance = PRBMath.mulDiv(20 ether, (WEIGHT / 10**18), 2);
    assertEq(_tokenStore.balanceOf(beneficiaryTwo, projectId), _userEthBalance);

    // verify: ETH balance in terminal should be up to date
    assertEq(jbPaymentTerminalStore().balanceOf(ETHterminal, projectId), 20 ether);


    // ---- Use allowance ----
    evm.startPrank(_projectOwner);
    ERC20terminal.useAllowanceOf(
      projectId,
      1, // amt
      jbLibraries().USD(), // Currency
      0, // Min wei out
      payable(msg.sender), // Beneficiary
      'MEMO'
    );
    evm.stopPrank();
    // assertEq(jbToken().balanceOf(msg.sender), 5*10**18);

    // // Distribute the funding target ETH -> no split then beneficiary is the project owner
    // uint256 initBalance = jbToken().balanceOf(_projectOwner);
    // evm.prank(_projectOwner);
    // terminal.distributePayoutsOf(
    //   projectId,
    //   10*10**18,
    //   1, // Currency
    //   0, // Min wei out
    //   'Foundry payment' // Memo
    // );
    // // Funds leaving the ecosystem -> fee taken
    // assertEq(jbToken().balanceOf(_projectOwner), initBalance + (10*10**18 * jbLibraries().MAX_FEE()) / (terminal.fee() + jbLibraries().MAX_FEE()) );

    // redeem eth from the overflow by the token holder:
    uint256 senderBalance = _tokenStore.balanceOf(msg.sender, projectId);

    evm.prank(msg.sender);
    ERC20terminal.redeemTokensOf(
      msg.sender,
      projectId,
      1,//senderBalance / (FAKE_PRICE*10**18),
      0,
      payable(msg.sender),
      'gimme my money back',
      new bytes(0)
    );

    // // verify: beneficiary should have a balance of 0 JBTokens
    // assertEq(_tokenStore.balanceOf(msg.sender, projectId), 0);
  }
}
