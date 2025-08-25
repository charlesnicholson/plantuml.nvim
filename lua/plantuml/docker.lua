local M = {}

local function is_windows()
  return vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
end

local function get_docker_cmd()
  return is_windows() and "docker.exe" or "docker"
end

local function run_command(cmd, callback)
  local shell_cmd
  if is_windows() then
    shell_cmd = { 'cmd', '/c', cmd }
  else
    shell_cmd = { 'sh', '-c', cmd }
  end
  
  if callback then
    vim.system(
      shell_cmd,
      {
        text = true,
        timeout = 120000,
      },
      function(obj)
        local success = obj.code == 0
        local result = obj.stdout or ""
        local error_output = obj.stderr or ""
        local full_output = result .. (error_output ~= "" and error_output or "")
        
        vim.schedule(function()
          callback(success and full_output or nil, success and nil or full_output)
        end)
      end
    )
  else
    local redirect_suffix = is_windows() and " 2>NUL" or " 2>&1"
    local handle = io.popen(cmd .. redirect_suffix)
    if not handle then
      return nil, "Failed to execute command"
    end
    
    local result = handle:read("*all")
    local success = handle:close()
    
    return success and result or nil, success and nil or result
  end
end

function M.is_docker_available(callback)
  local docker_cmd = get_docker_cmd()
  local cmd = docker_cmd .. " --version"
  
  local function check_result(result, err)
    local available = result ~= nil and result:match("Docker version")
    return available, err
  end
  
  if callback then
    run_command(cmd, function(result, err)
      local available, error = check_result(result, err)
      callback(available, error)
    end)
  else
    local result, err = run_command(cmd)
    return check_result(result, err)
  end
end

function M.is_docker_running(callback)
  local docker_cmd = get_docker_cmd()
  local cmd = docker_cmd .. " info"
  
  local function check_result(result, err)
    local is_running = result ~= nil and not result:match("Cannot connect to the Docker daemon")
    return is_running, err
  end
  
  if callback then
    run_command(cmd, function(result, err)
      local is_running, error = check_result(result, err)
      callback(is_running, error)
    end)
  else
    local result, err = run_command(cmd)
    return check_result(result, err)
  end
end

function M.get_container_status(container_name, callback)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s ps -a --filter "name=%s" --format "{{.Status}}"', docker_cmd, container_name)
  
  local function parse_status(result, err)
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
  
  if callback then
    run_command(cmd, function(result, err)
      local status, error = parse_status(result, err)
      callback(status, error)
    end)
  else
    local result, err = run_command(cmd)
    return parse_status(result, err)
  end
end

function M.get_container_port(container_name, internal_port)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s port %s %s', docker_cmd, container_name, internal_port)
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

function M.start_container(container_name, image, host_port, internal_port, callback)
  local docker_cmd = get_docker_cmd()
  
  local function start_existing()
    local cmd = string.format('%s start %s', docker_cmd, container_name)
    if callback then
      run_command(cmd, function(result, err)
        callback(result ~= nil, err or "Failed to start existing container")
      end)
    else
      local result, err = run_command(cmd)
      return result ~= nil, err or "Failed to start existing container"
    end
  end
  
  local function create_new()
    local cmd = string.format('%s run -d --name %s -p %d:%d %s', 
                             docker_cmd, container_name, host_port, internal_port, image)
    if callback then
      run_command(cmd, function(result, err)
        callback(result ~= nil, err or "Failed to create and start container")
      end)
    else
      local result, err = run_command(cmd)
      return result ~= nil, err or "Failed to create and start container"
    end
  end
  
  if callback then
    M.get_container_status(container_name, function(status, _)
      if status == "running" then
        callback(true, "Container already running")
      elseif status == "stopped" then
        start_existing()
      else
        create_new()
      end
    end)
  else
    local status, _ = M.get_container_status(container_name)
    if status == "running" then
      return true, "Container already running"
    elseif status == "stopped" then
      return start_existing()
    else
      return create_new()
    end
  end
end

function M.stop_container(container_name)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s stop %s', docker_cmd, container_name)
  local result, err = run_command(cmd)
  return result ~= nil, err
end

function M.remove_container(container_name)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s rm %s', docker_cmd, container_name)
  local result, err = run_command(cmd)
  return result ~= nil, err
end

function M.wait_for_container_ready(container_name, timeout_seconds, callback)
  timeout_seconds = timeout_seconds or 30
  local start_time = os.time()
  
  local function check_status()
    if callback then
      M.get_container_status(container_name, function(status, _)
        if status == "running" then
          callback(true, nil)
        elseif os.time() - start_time >= timeout_seconds then
          callback(false, "Container failed to start within timeout")
        else
          vim.defer_fn(check_status, 1000)
        end
      end)
    else
      local status, _ = M.get_container_status(container_name)
      if status == "running" then
        return true, nil
      elseif os.time() - start_time >= timeout_seconds then
        return false, "Container failed to start within timeout"
      else
        vim.wait(1000)
        return check_status()
      end
    end
  end
  
  return check_status()
end

function M.pull_image(image)
  local docker_cmd = get_docker_cmd()
  local cmd = string.format('%s pull %s', docker_cmd, image)
  local result, err = run_command(cmd)
  local success = result ~= nil
  return success, err
end

return M