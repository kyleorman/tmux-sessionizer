# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- BATS test suite with 15 tests
- `--help` and `--version` flags
- `--validate` flag for configuration validation
- Session preview in fzf interface
- Context-aware fzf height autodetection (`40%` inside tmux, `100%` outside tmux)
- Collision-aware session naming
- Session template support with auto-detection
- Standardized error/warning functions
- Exit code constants for better error handling
- Comprehensive documentation (CONTRIBUTING.md, examples/)

### Changed
- Refactored configuration handling into functions
- Improved code organization with clear sections
- Enhanced error messages with context
- Replaced `eval` with safe variable expansion

### Fixed
- Security vulnerability in config parsing (removed eval)
- Edge case handling (empty dirs, permissions, etc.)
- Proper exit codes for different error conditions

### Security
- Fixed arbitrary code execution vulnerability in config file parsing
