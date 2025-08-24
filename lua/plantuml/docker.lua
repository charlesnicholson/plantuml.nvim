local M = {}

local function run_command(cmd, callback)
  vim.notify("[plantuml.nvim] Docker debug: Executing command: " .. cmd, vim.log.levels.DEBUG)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    local err_msg = "Failed to execute command"
    vim.notify("[plantuml.nvim] Docker debug: " .. err_msg, vim.log.levels.DEBUG)
    if callback then callback(nil, err_msg) end
    return nil, err_msg
  end
  
  local result = handle:read("*all")
  local success = handle:close()
  
  vim.notify("[plantuml.nvim] Docker debug: Command result (success=" .. tostring(success) .. "): " .. (result or "nil"), vim.log.levels.DEBUG)
  
  if callback then
    callback(success and result or nil, success and nil or result)
  end
  
  return success and result or nil, success and nil or result
end

local function is_windows()
  return vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
end

local function get_docker_cmd()
  return is_windows() and "docker.exe" or "docker"
end

function M.is_docker_available()
  vim.notify("[plantuml.nvim] Docker debug: Checking Docker availability", vim.log.levels.DEBUG)
  local docker_cmd = get_docker_cmd()
  vim.notify("[plantuml.nvim] Docker debug: Using Docker command: " .. docker_cmd, vim.log.levels.DEBUG)
  local result, err = run_command(docker_cmd .. " --version")
  local available = result ~= nil and result:match("Docker version")
  vim.notify("[plantuml.nvim] Docker debug: Docker available: " .. tostring(available) .. (err and (" (error: " .. err .. ")") or ""), vim.log.levels.DEBUG)
  return available, err
end

function M.is_docker_running()
  vim.notify("[plantuml.nvim] Docker debug: Checking if Docker daemon is running", vim.log.levels.DEBUG)
  local docker_cmd = get_docker_cmd()
  local result, err = run_command(docker_cmd .. " info")
  local is_running = result ~= nil and not result:match("Cannot connect to the Docker daemon")
  vim.notify("[plantuml.nvim] Docker debug: Docker daemon running: " .. tostring(is_running) .. (err and (" (error: " .. err .. ")") or ""), vim.log.levels.DEBUG)
  return is_running, err
end

function M.get_container_status(container_name)
  vim.notify("[plantuml.nvim] Docker debug: Getting container status for: " .. container_name, vim.log.levels.DEBUG)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s ps -a --filter "name=%s" --format "{{.Status}}"', docker_cmd, container_name)
  local result, err = run_command(cmd)
  
  if not result or result:match("^%s*$") then
    vim.notify("[plantuml.nvim] Docker debug: Container not found or empty result", vim.log.levels.DEBUG)
    return "not_found", nil
  end
  
  result = result:gsub("%s+$", "")
  vim.notify("[plantuml.nvim] Docker debug: Raw container status: '" .. result .. "'", vim.log.levels.DEBUG)
  
  local status
  if result:match("^Up") then
    status = "running"
  elseif result:match("^Exited") then
    status = "stopped"
  else
    status = "unknown"
  end
  
  vim.notify("[plantuml.nvim] Docker debug: Parsed container status: " .. status, vim.log.levels.DEBUG)
  return status, status == "unknown" and result or nil
end

function M.get_container_port(container_name, internal_port)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s port %s %s 2>/dev/null', docker_cmd, container_name, internal_port)
  local result, err = run_command(cmd)
  
  if not result or result:match("^%s*$") then
    return nil, "Container not found or port not mapped"
  end
  
  local port = result:match("0%.0%.0%.0:(%d+)")
  if not port then
    port = result:match("127%.0%.0%.1:(%d+)")
  end
  
  return port and tonumber(port) or nil, port and nil or "Port mapping not found"
end

function M.start_container(container_name, image, host_port, internal_port)
  vim.notify("[plantuml.nvim] Docker debug: Starting container - name: " .. container_name .. 
             ", image: " .. image .. ", host_port: " .. host_port .. ", internal_port: " .. internal_port, vim.log.levels.DEBUG)
  local docker_cmd = get_docker_cmd()
  
  local status, _ = M.get_container_status(container_name)
  vim.notify("[plantuml.nvim] Docker debug: Current container status: " .. status, vim.log.levels.DEBUG)
  
  if status == "running" then
    vim.notify("[plantuml.nvim] Docker debug: Container already running, returning success", vim.log.levels.DEBUG)
    return true, "Container already running"
  elseif status == "stopped" then
    vim.notify("[plantuml.nvim] Docker debug: Container exists but stopped, attempting to start", vim.log.levels.DEBUG)
    local cmd = string.format('%s start %s', docker_cmd, container_name)
    local result, err = run_command(cmd)
    local success = result ~= nil
    vim.notify("[plantuml.nvim] Docker debug: Container start result: " .. tostring(success) .. 
               (err and (" (error: " .. err .. ")") or ""), vim.log.levels.DEBUG)
    return success, err or "Failed to start existing container"
  else
    vim.notify("[plantuml.nvim] Docker debug: Container not found, creating new container", vim.log.levels.DEBUG)
    local cmd = string.format('%s run -d --name %s -p %d:%d %s', 
                             docker_cmd, container_name, host_port, internal_port, image)
    vim.notify("[plantuml.nvim] Docker debug: Docker run command: " .. cmd, vim.log.levels.DEBUG)
    local result, err = run_command(cmd)
    local success = result ~= nil
    vim.notify("[plantuml.nvim] Docker debug: Container creation result: " .. tostring(success) .. 
               (err and (" (error: " .. err .. ")") or ""), vim.log.levels.DEBUG)
    return success, err or "Failed to create and start container"
  end
end

function M.stop_container(container_name)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s stop %s 2>/dev/null', docker_cmd, container_name)
  local result, err = run_command(cmd)
  return result ~= nil, err
end

function M.remove_container(container_name)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s rm %s 2>/dev/null', docker_cmd, container_name)
  local result, err = run_command(cmd)
  return result ~= nil, err
end

function M.wait_for_container_ready(container_name, timeout_seconds)
  timeout_seconds = timeout_seconds or 30
  vim.notify("[plantuml.nvim] Docker debug: Waiting for container to be ready - timeout: " .. timeout_seconds .. "s", vim.log.levels.DEBUG)
  local start_time = os.time()
  
  while os.time() - start_time < timeout_seconds do
    local status, _ = M.get_container_status(container_name)
    vim.notify("[plantuml.nvim] Docker debug: Container status during wait: " .. status, vim.log.levels.DEBUG)
    if status == "running" then
      vim.notify("[plantuml.nvim] Docker debug: Container is now running", vim.log.levels.DEBUG)
      return true, nil
    end
    vim.wait(1000)
  end
  
  vim.notify("[plantuml.nvim] Docker debug: Container failed to be ready within timeout", vim.log.levels.DEBUG)
  return false, "Container failed to start within timeout"
end

function M.pull_image(image)
  vim.notify("[plantuml.nvim] Docker debug: Pulling image: " .. image, vim.log.levels.DEBUG)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s pull %s', docker_cmd, image)
  local result, err = run_command(cmd)
  local success = result ~= nil
  vim.notify("[plantuml.nvim] Docker debug: Image pull result: " .. tostring(success) .. 
             (err and (" (error: " .. err .. ")") or ""), vim.log.levels.DEBUG)
  return success, err
end

return M