
module ol_framework::fee_maker {

    use ol_framework::system_addresses;
    use diem_framework::account;
    use diem_framework::create_signer;
    use std::vector;
    use std::signer;



    friend diem_framework::transaction_fee;
    friend diem_framework::genesis;
    friend ol_framework::epoch_boundary;

    /// FeeMaker struct lives on an individual's account
    /// We check how many fees the user has paid.
    /// This will interact with Burn preferences when there is a remainder of fees in the TransactionFee account
    struct FeeMaker has key {
      epoch: u64,
      lifetime: u64,
    }

    /// We need a list of who is producing fees this epoch.
    /// This lives on the VM address
    struct EpochFeeMakerRegistry has key {
      fee_makers: vector<address>,
      epoch_fees_made: u64,
    }

    /// Initialize the registry at the VM address.
    public(friend) fun initialize(ol_framework: &signer) {
      system_addresses::assert_ol(ol_framework);
      if (!exists<EpochFeeMakerRegistry>(@ol_framework)) {
        let registry = EpochFeeMakerRegistry {
          fee_makers: vector::empty(),
          epoch_fees_made: 0,
        };
        move_to(ol_framework, registry);
      }
    }

    /// FeeMaker is initialized when the account is created
    /// Lazy initialization since very few accounts will need this struct
    fun maybe_initialize_fee_maker(sig: &signer) {
      let account = signer::address_of(sig);
      if (system_addresses::is_reserved_address(account) || system_addresses::is_framework_reserved_address(account)) return;

      if (!exists<FeeMaker>(account)) {

        move_to(sig, FeeMaker {
          epoch: 0,
          lifetime: 0,
        });
      };
    }

    // TODO: this needs to be refactored to use the migration capability
    /// the VM may need to migrate an account on the fly if it has not been initialized with fee maker.
    fun maybe_vm_initialize_fee_maker(framework: &signer, account: address,) {
      system_addresses::assert_diem_framework(framework);

      if (system_addresses::is_reserved_address(account) || system_addresses::is_framework_reserved_address(account)) return;

      if (!exists<FeeMaker>(account)) {
        // TODO: this should only be done with a MigrationCapability
        // sometimes the VM needs to initialize an account
        let sig = &create_signer::create_signer(account);

        move_to(sig, FeeMaker {
          epoch: 0,
          lifetime: 0,
        });
      };
    }

    public(friend) fun epoch_reset_fee_maker(vm: &signer): bool acquires EpochFeeMakerRegistry, FeeMaker {
      system_addresses::assert_ol(vm);
      let registry = borrow_global_mut<EpochFeeMakerRegistry>(@ol_framework);
      let fee_makers = &registry.fee_makers;
      let i = 0;
      while (i < vector::length(fee_makers)) {
        let account = *vector::borrow(fee_makers, i);
        // belt and suspenders for dropped accounts in hard fork.
        if (!account::exists_at(account)) {
          i = i + 1;
          continue
        };
        reset_one_fee_maker(vm, account);
        i = i + 1;
      };
      registry.fee_makers = vector::empty();
      registry.epoch_fees_made = 0;

      vector::length(&registry.fee_makers) == 0
    }

    /// FeeMaker is reset at the epoch boundary, and the lifetime is updated.
    fun reset_one_fee_maker(vm: &signer, account: address) acquires FeeMaker {
      system_addresses::assert_ol(vm);
      if (!exists<FeeMaker>(account)) return ;
      let fee_maker = borrow_global_mut<FeeMaker>(account);
        fee_maker.lifetime = fee_maker.lifetime + fee_maker.epoch;
        fee_maker.epoch = 0;
    }

    /// add a fee to the account fee maker for an epoch.
    // lazy initialize structs
    // should only be called by
    public(friend) fun track_user_fee(user_sig: &signer, amount: u64) acquires FeeMaker, EpochFeeMakerRegistry {
      let account = signer::address_of(user_sig);
      if (system_addresses::is_reserved_address(account) || system_addresses::is_framework_reserved_address(account)) return;

      if (amount == 0) return;

      maybe_initialize_fee_maker(user_sig);
      track_user_fee_impl(signer::address_of(user_sig), amount);
    }

    /// maybe the VM needs to track on behalf of a user
    // should also lazily initialize structs
    public(friend) fun vm_track_user_fee(framework: &signer, account: address, amount: u64) acquires FeeMaker, EpochFeeMakerRegistry {
      system_addresses::assert_diem_framework(framework);
      // will not initialize, and the fee will not be tracked
      maybe_vm_initialize_fee_maker(framework, account);
      track_user_fee_impl(account, amount);
    }

    public(friend) fun track_user_fee_impl(account: address, amount: u64) acquires FeeMaker, EpochFeeMakerRegistry {

      if (!exists<FeeMaker>(account)) return;

      let fee_maker = borrow_global_mut<FeeMaker>(account);
      fee_maker.epoch = fee_maker.epoch + amount;

      // update the registry
      let registry = borrow_global_mut<EpochFeeMakerRegistry>(@ol_framework);
      if (!vector::contains(&registry.fee_makers, &account)) {
        vector::push_back(&mut registry.fee_makers, account);
      };
      registry.epoch_fees_made = registry.epoch_fees_made + amount;
    }

    //////// GETTERS ///////

    #[view]
    // get list of fee makers
    public fun get_fee_makers(): vector<address> acquires EpochFeeMakerRegistry {
      let registry = borrow_global<EpochFeeMakerRegistry>(@ol_framework);
      *&registry.fee_makers
    }

    #[view]
    /// get the fees made by the user in the epoch
    public fun get_user_fees_made(account: address): u64 acquires FeeMaker {
      if (!exists<FeeMaker>(account)) {
        return 0
      };
      let fee_maker = borrow_global<FeeMaker>(account);
      fee_maker.epoch
    }

    #[view]
    /// get total fees made across all epochs
    public fun get_all_fees_made(): u64 acquires EpochFeeMakerRegistry {
      if (!exists<EpochFeeMakerRegistry>(@ol_framework)) return 0;

      let registry = borrow_global<EpochFeeMakerRegistry>(@ol_framework);
      registry.epoch_fees_made
    }

}
