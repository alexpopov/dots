## Find

So you can move around your immediate area. Good job! Now let's find exactly what we're looking for. 

While in Normal Mode, you can type `/` to start doing a regular expression search. 
At its most basic, after you type `/` you can type a string you want to find and then hit enter to jump there. 

Now you can hit `n` to go to the **next** match. How do we go to a previous match? Well, vim seems to mix its input metaphors occasionally, so in this case we do the opposite by pressing Shift. That is, `n` is next and `Shift-n` is the opposite. Vim saves your last search, so you can hit `n` or `N` again to go to the next instance even after editing text or moving elsewhere. 

As you jump around a file in this way, you can also use `C-o` to go "out" to where you were before, and `C-i` to go back "in" to where you got out of. This mirrors the behavior of `n`/`N` but works with many movement commands even across files. You can press \`\` to go back to where you were before the search. 

This basic search method isn't great: if you type something that matches nothing, you won't find out until after you hit enter. To fix this, we type `:set incsearch` for "Incremental Search". From now on, searches will update as we type them. If as we type our search stops yielding results, we'll know it's either not here or we misspelled it. We can save this behavior by putting it into our `.vimrc` or `init.vim`:

```
set incsearch  " incremental search
```

Let's step it up a notch further by adding two more options to our config file:

```
set ignorecase " ignores case
set smartcase  " lowercase searches will match all 
```

Combined, these two options have some desirable properties:
  - if we type all lowercase, it'll match _any_ case, e.g. `lower` will match `lower`, `Lower` and `LOWER`. 
  - if include a capital it'll treat the whole string as depending on case, so that `loWer` will only match `loWer`. 

This is handy when searching camel-cased codebases because we can save ourselves some mistakes by just typing `xmlst` if we can't remember if Java prefers acronyms to be capitalized (`XMLStream`) or treated as a single word (`XmlStream`)—it's the latter by the way—but `xmlst` will match both. 

If we ever do want to search for an explicitly lower-case string, we can preface our search with `\C`, e.g. `/\Cxml` will only match `xml` and not `Xml`. Why `\C`? This actually follows the same convention as moving between next and previous matches: `\c` makes a search case-insensitive, so the capitalized (shifted?) version does the opposite. 

## Regex 

But why the backslash in `\C`? As you may already know, backslashes are used to "escape" metasymbols. For example, if we think of strings as being delimited by quotes `"`, how would we write a string that contained a quote? Almost always, by backslash-escaping it: `"\"To be, or not to be...\", he said to himself"`. 

Similarly, we can imbue characters with special properties, such as the `c` above. Usually, the letter `c` is unassuming, but with a backslash it becomes metadata about our search, specifically case sensitivity. 

These special search strings are called [regular expressions](https://en.wikipedia.org/wiki/Regular_expression) (regex for short).  There is a mathematical definition of what a regex is, but most tools permit a looser form, which is the one we'll be using. There are also different flavors of regex. Vim has its own flavor. [It can get really complicated](http://vimregex.com).

Regex is a valuable language to learn and even basic regex knowledge can make you significantly more powerful in vim. I highly recommend learning regex on your own time. 

Here's a quick example: 

```
/^\s*def\s
```

  - `^`: start at the beginning of the line
  - `\s`: whitespace character; space, tab, newline, etc. 
  - `*`: zero or more
  - `def`: the literal letters `d`, `e`, `r`

So this will match a `def` that is zero or more spaces from the start of a line, following by another space. If we bound this to a command we could easily jump between definitions in Python. Combining it with `n`/`N` we could move through a file and explore its API at lightning speed.

## Substitute

Once we match a pattern we could also replace it with something else using the `:s` command. 

`:s/pattern/replacement/` will find the *first* instance of `pattern` on every line and replace it with `replacement`.

We can add some _flags_ to the end of the command to subtly change it.
  -  `g` (for _global_) will match all instances and not just the first on a line
  - `c` will prompt you to _confirm_ each change. 
  - `i` will _ignore_ case of the pattern string; `I` does the opposite. 

Let's look at a simple example. Suppose you wrote a report where you refer to yourself in the singular, but then last minute your friend asks if they can form a team with you to freeload off your hard work. You begrudgingly accept, but now you need to change all uses of "I" into "we". One reasonable way (though not the best) is with the following: 

```
:s/I/we/gc
```

This will match capital "I" in proper nouns and the start of sentences, so we want to confirm each case. A single line may have multiple instances of the letter "I", so we modify our search to be global. 

-----------

And that's it! There's a lot more that you can do with regular expressions and vim, but you'll learn as you find the need for more power. Once we learn how to use plugins we'll have even more flexible types of search across all kinds of contexts. 
