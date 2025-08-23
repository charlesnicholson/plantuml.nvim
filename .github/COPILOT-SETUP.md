# GitHub Copilot Development Environment Setup

This directory contains reusable setup steps extracted from the main functional tests workflow to help GitHub Copilot agents quickly set up development environments for testing plantuml.nvim.

## Files

### `copilot-setup-steps.yml`
A reusable workflow that can be called by other workflows to set up the complete development environment.

**Usage in workflows:**
```yaml
jobs:
  my-job:
    uses: ./.github/workflows/copilot-setup-steps.yml
```

### `actions/setup-dev-env/action.yml`
A composite action that provides more flexibility with optional steps.

**Usage in workflows:**
```yaml
- name: Setup development environment
  uses: ./.github/actions/setup-dev-env
  
# Or with options:
- name: Setup development environment (minimal)
  uses: ./.github/actions/setup-dev-env
  with:
    skip-playwright: 'true'
    skip-virtual-display: 'true'
```

## What Gets Installed

Both setup methods install and configure:

1. **System Dependencies**
   - curl, wget, unzip
   - xvfb (for headless browser testing)
   - nodejs, npm

2. **Neovim**
   - Latest version from PPA
   - Verification that it works correctly

3. **Node.js Dependencies**
   - npm packages from package.json
   - Playwright with chromium browser

4. **Test Environment**
   - Runs `./tests/setup-test-env.sh`
   - Creates test directories and fixtures
   - Sets up minimal Neovim config for testing

5. **Virtual Display**
   - Xvfb on display :99 for headless browser testing
   - Sets DISPLAY environment variable

## Available Test Scripts

After setup, you can run individual test scripts:

```bash
./tests/test-plugin-loading.sh      # Test plugin loads correctly
./tests/test-http-server.sh         # Test HTTP server functionality  
./tests/test-websocket.sh           # Test WebSocket server
./tests/test-plantuml-processing.sh # Test PlantUML diagram processing
./tests/test-browser-ui.sh          # Test browser UI interactions
```

## For Copilot Agents

These setup steps allow Copilot to:

1. Quickly bootstrap a development environment
2. Run tests locally before committing changes
3. Validate plugin functionality end-to-end
4. Debug issues with HTTP/WebSocket servers
5. Test browser UI interactions

The setup is designed to be:
- **Fast**: Installs only necessary dependencies
- **Reliable**: Uses stable package sources and verification steps
- **Flexible**: Optional components can be skipped
- **Comprehensive**: Covers all testing scenarios

## Local Development

To use these setup steps for local development:

1. Install system dependencies manually or use the action
2. Run `./tests/setup-test-env.sh` to create test environment
3. Execute individual test scripts to validate changes
4. Use virtual display for browser testing: `DISPLAY=:99 ./tests/test-browser-ui.sh`