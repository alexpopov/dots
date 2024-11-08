  if os.getenv("ENABLE_PRIVATE_FACEBOOK")
  then
    return { "meta", dir = "/home/alexpopov/fbsource/fbcode/editor_support/nvim", }
  else
    return {}
  end

