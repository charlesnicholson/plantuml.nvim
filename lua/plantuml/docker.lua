-- Docker container lifecycle management.
-- Async-only: every function takes a callback. Uses vim.system() with argument arrays.

local M = {}

local function docker_cmd()
  return (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1) and "docker.exe" or "docker"
end

local function run(args, cb)
  vim.system(args, { text = true, timeout = 120000 }, function(obj)
    vim.schedule(function()
      cb(obj.code == 0, obj.stdout or "", obj.stderr or "")
    end)
  end)
end

function M.is_docker_available(cb)
  run({ docker_cmd(), "--version" }, function(ok, stdout)
    cb(ok and stdout:match("Docker version") ~= nil)
  end)
end

function M.is_docker_running(cb)
  run({ docker_cmd(), "info" }, function(ok, stdout, stderr)
    local output = stdout .. stderr
    cb(ok and not output:match("Cannot connect to the Docker daemon"))
  end)
end

function M.get_container_status(name, cb)
  run({ docker_cmd(), "ps", "-a", "--filter", "name=^/" .. name .. "$", "--format", "{{.Status}}" },
    function(ok, stdout)
      if not ok or stdout:match("^%s*$") then
        cb("not_found")
        return
      end
      stdout = stdout:gsub("%s+$", "")
      if stdout:match("^Up") then
        cb("running")
      elseif stdout:match("^Exited") then
        cb("stopped")
      else
        cb("unknown")
      end
    end)
end

local function get_host_port(name, cb)
  run({
    docker_cmd(), "inspect", name,
    "--format", "{{(index (index .NetworkSettings.Ports \"8080/tcp\") 0).HostPort}}",
  }, function(ok, stdout)
    if ok then
      cb(stdout:match("(%d+)"))
    else
      cb(nil)
    end
  end)
end

local function recreate_container(name, image, host_port, container_port, cb)
  run({ docker_cmd(), "rm", "-f", name }, function()
    run({
      docker_cmd(), "run", "-d",
      "--name", name,
      "-p", host_port .. ":" .. container_port,
      image,
    }, function(ok)
      cb(ok)
    end)
  end)
end

function M.start_container(name, image, host_port, container_port, cb)
  M.get_container_status(name, function(status)
    if status == "running" then
      get_host_port(name, function(actual_port)
        if actual_port == tostring(host_port) then
          cb(true)
        else
          recreate_container(name, image, host_port, container_port, cb)
        end
      end)
    elseif status == "stopped" then
      get_host_port(name, function(actual_port)
        if actual_port == tostring(host_port) then
          run({ docker_cmd(), "start", name }, function(ok)
            cb(ok)
          end)
        else
          recreate_container(name, image, host_port, container_port, cb)
        end
      end)
    else
      run({
        docker_cmd(), "run", "-d",
        "--name", name,
        "-p", host_port .. ":" .. container_port,
        image,
      }, function(ok)
        cb(ok)
      end)
    end
  end)
end

function M.stop_container(name, cb)
  run({ docker_cmd(), "stop", name }, function(ok)
    cb(ok)
  end)
end

function M.remove_container(name, cb)
  run({ docker_cmd(), "rm", name }, function(ok)
    cb(ok)
  end)
end

function M.wait_for_ready(name, timeout_sec, cb)
  local timer = vim.uv.new_timer()
  local elapsed = 0

  local function check()
    if elapsed >= timeout_sec then
      timer:stop()
      timer:close()
      cb(false, "timeout")
      return
    end
    M.get_container_status(name, function(status)
      if status == "running" then
        timer:stop()
        timer:close()
        cb(true)
      end
      -- Otherwise keep polling (timer fires again)
    end)
    elapsed = elapsed + 1
  end

  -- First check immediately
  check()
  -- Then poll every 1s
  timer:start(1000, 1000, vim.schedule_wrap(function()
    check()
  end))
end

return M
