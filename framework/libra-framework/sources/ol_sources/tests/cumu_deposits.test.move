
#[test_only]

module ol_framework::test_cumu_deposits {
    use ol_framework::ol_account;
    use ol_framework::cumulative_deposits;
    use ol_framework::receipts;
    use ol_framework::mock;
    use std::timestamp;

    #[test(root = @ol_framework, alice = @0x1000a)]
    fun cumu_deposits_init(root: &signer, alice: &signer) {
      mock::genesis_n_vals(root, 2);
      cumulative_deposits::test_init_cumulative_deposits(alice);

      assert!(cumulative_deposits::is_init_cumu_tracking(@0x1000a), 7357001);
      let t = cumulative_deposits::get_cumulative_deposits(@0x1000a);
      assert!(t == 0, 7357002);

      // also check bob is properly initialized
      assert!(receipts::is_init(@0x1000b), 7357003);
    }

    #[test(root = @ol_framework, alice = @0x1000a, bob = @0x1000b)]
    fun cumu_deposits_track(root: &signer, alice: &signer, bob: &signer) {
      mock::genesis_n_vals(root, 2);
      mock::ol_initialize_coin_and_fund_vals(root, 10000, true);
      cumulative_deposits::test_init_cumulative_deposits(alice);

      assert!(cumulative_deposits::is_init_cumu_tracking(@0x1000a), 7357001);
      let t = cumulative_deposits::get_cumulative_deposits(@0x1000a);
      assert!(t == 0, 7357002);

      assert!(receipts::is_init(@0x1000b), 7357003);

      let bob_donation = 42;
      let new_time = 1000;
      timestamp::fast_forward_seconds(new_time);
      ol_account::transfer(bob, @0x1000a, bob_donation); // this should track

      let (a, b, c) = receipts::read_receipt(@0x1000b, @0x1000a);
      assert!(a != 1, 7357004); // timestamp is not genesis
      assert!(b == bob_donation, 7357005); // last payment
      assert!(c == bob_donation, 7357006); // cumulative payments

      let alice_cumu = cumulative_deposits::get_cumulative_deposits(@0x1000a);
      assert!(alice_cumu == bob_donation, 7357007);

    }
}
