I use this for serving an LLM with Ollama from my local machine to my remote server where I have Karakeep setup in Coolify. This way Karakeep can utilize the LLM to generate tags and make AI summaries for my bookmarks.

# todo
- [x] cleanup double output when closing
- [x] if ollama was already running don't kill it.
- [ ] make a config file somewhere
- [ ] rewrite with nicer TUI. ncurses? bubbletea? 
  - [ ] display some kind of throbber when ollama generates text
- [ ] stop over engineering after this
