local M = {}

local function run_command(cmd, callback)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    if callback then callback(nil, "Failed to execute command") end
    return nil, "Failed to execute command"
  end
  
  local result = handle:read("*all")
  local success = handle:close()
  
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
  local docker_cmd = get_docker_cmd()
  local result, err = run_command(docker_cmd .. " --version")
  return result ~= nil and result:match("Docker version"), err
end

function M.is_docker_running()
  local docker_cmd = get_docker_cmd()
  local result, err = run_command(docker_cmd .. " info")
  return result ~= nil and not result:match("Cannot connect to the Docker daemon"), err
end

function M.get_container_status(container_name)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s ps -a --filter "name=%s" --format "{{.Status}}"', docker_cmd, container_name)
  local result, err = run_command(cmd)
  
  if not result or result:match("^%s*$") then
    return "not_found", nil
  end
  
  result = result:gsub("%s+$", "")
  
  if result:match("^Up") then
    return "running", nil
  elseif result:match("^Exited") then
    return "stopped", nil
  else
    return "unknown", result
  end
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
  local docker_cmd = get_docker_cmd()
  
  local status, _ = M.get_container_status(container_name)
  
  if status == "running" then
    return true, "Container already running"
  elseif status == "stopped" then
    local cmd = string.format('%s start %s', docker_cmd, container_name)
    local result, err = run_command(cmd)
    return result ~= nil, err or "Failed to start existing container"
  else
    local cmd = string.format('%s run -d --name %s -p %d:%d %s', 
                             docker_cmd, container_name, host_port, internal_port, image)
    local result, err = run_command(cmd)
    return result ~= nil, err or "Failed to create and start container"
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
  local start_time = os.time()
  
  while os.time() - start_time < timeout_seconds do
    local status, _ = M.get_container_status(container_name)
    if status == "running" then
      return true, nil
    end
    vim.wait(1000)
  end
  
  return false, "Container failed to start within timeout"
end

function M.pull_image(image)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s pull %s', docker_cmd, image)
  local result, err = run_command(cmd)
  return result ~= nil, err
end

return M