  if os.getenv("ENABLE_PRIVATE_FACEBOOK")
  then
    return { "/home/alexpopov/fbsource/fbcode/editor_support/nvim", as = "meta" }
  else
    return {}
  end

