# Contributing to HarvOS

We welcome contributions! Before submitting:

1. **Fork** the repo and create a feature branch.
2. Run lint + sim:  
   ```bash
   verilator --lint-only rtl/*.sv
   make test
   ```
3. Add or update testbenches to cover new features.
4. Submit a pull request with a clear description.

## Style
- SystemVerilog 2012
- 2-space indentation
- `logic` instead of `reg/wire`
- One module per file

## License
By contributing, you agree that your contributions will be licensed
under the Apache 2.0 + SHL license.
