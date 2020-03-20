While using `hjkl` or arrows for movement is cute, it's horribly slow—especially if your key-repeat time is low. There are many better options, but today we'll take a look at just a few of the options for moving by _word-objects_. 

The most basic form of movement is using arrow keys to move character-by-character or line-by-line. But within a line we also have more important groupings of characters: words. Vim has a specific definition of what it means to be a "word" and you can move between words quickly with just a few key presses. You can read about these by typing `:help word-motions` in Vim. 

Let's start with a pair of anchors: `^` and `$`. 
  - `^` moves to the first non-whitespace character on a line
  - `$` moves to the last character on a line 

More info on these is available at `:help left-right-motions`. Conveniently, these characters also have similar meanings in regular expressions. 

Now suppose we have the following line: 

```
  the quick brown-fox jumpedOverThe lazy dog
```

Pressing `$` will obviously move us to the end:
```
  the quick brown-fox jumpedOverThe lazy dog
                                           ^
```
And pressing `^` will move us to the first letter:
```
  the quick brown-fox jumpedOverThe lazy dog
  ^                                         
```

But how do we get to "quick"? We could certainly hit `l` 4 times. We could even type `4l` and feel like pros! But there is an easier way. `w`. 

## Words, words, words

`w` will move us to the first character of the next word. `w` is for "word". Try it out. 

As you press `w` a couple times in the line you'll stop at the following spots: 

```
  the quick brown-fox jumpedOverThe lazy dog
  ^   ^     ^    ^^   ^             ^    ^         
```

This works mostly as expected, but also highlights that vim's understanding of "words" isn't necessarily exactly the same as ours. Vim treats hyphens as individual words but doesn't care about camelCase. Incidentally, it treats snake\_cased\_words as single words for the purposes of movement. 

Let's take a look at how this works in a line of code: 

```
if not ty.is_convertable_score(argument_score):
```

What we'll find is that the definition of a "word" is fairly convenient here, letting us move between meaningful objects without vim understanding anything about Python: 

```
if not ty.is_convertable_score(argument_score):
^  ^   ^ ^^                   ^^             ^
```

We can speed up movement even more by pressing shift to make it a capital `W`. This relaxes the definition of "word" to just mean groups of text separated by whitespace (vim calls these WORDS as opposed to _words_). This treats `ty.is_convertable_score(argument_score):` as a single giant word, letting us skip past it in a single key press. 

Many commands have a capitalized variant in this way which performs a similar function. 

## More Words 

`w` allows us to move forward to the start of a word, but what if we wanted to append something to the current one? We could move to the "end" of a word with `e`. This command follows all of the same rules as `w` with respect to what a "word" is:

```
  the quick brown-fox jumpedOverThe lazy dog
    ^     ^     ^^  ^             ^    ^   ^
```

As you may expect, capital `E` will move between WORDS instead of _words_. 

But what about moving backwards (to the beginning)? Enter `b` and `B`. I think you can figure these two out. 

From reading the docs on this (`:help word-motions`) I also learned that there are `ge` and `gE`, which are like `b` but for going to the _end_ of a previous word. It's there if you want it, but I just stick to `w`, `e` and `b`. 

## Wrap up

These movement commands significantly speed up movement across a line and lie quite close to home row. `e` and `w` are both in your left hand and move to right; `b` is in your right hand and moves to the left. A day or two and muscle memory takes care of the rest. 

## Bonus Tip

Bonus tip is reserved for simple things I assume you already know, but if you don't, they're really handy and easy to integrate. 

One thing we saw today was how capitalizing a letter changed its effect. This also happens with `a` and `i`. As you know, `i` starts insertion at your cursor and `a` starts insertion after your cursor—this is why I like to use a block cursor as opposed to a line; it makes `a`'s behavior easier to visualize at the spot. 

If we press shift:

  - `I` will go to the start of the line and enter insertion mode. This is the same as pressing `^i`. 
  - `A` will go the _end_ of the line and enter insertion mode. This is the same as pressing `$a`. 

Happy viming! 
