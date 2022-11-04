# How to build the workshop

## Flat HTML output with pandoc

~~~
pandoc -s -o /tmp/workshop-PAF.html workshop-PAF.md
~~~

## Slide output with reveal and pandoc

Download and extract reveal.js to /tmp/reveal.js:

~~~
cd /tmp
wget https://github.com/hakimel/reveal.js/archive/master.zip
unzip master.zip
mv reveal.js-master reveal.js
~~~

Now you can build a self-contained html file:

~~~
pandoc -t revealjs --variable=revealjs-url:/tmp/reveal.js workshop-PAF.md --self-contained --standalone -o /tmp/paf.html
~~~

Note: if you have an internet access you can build html files without downloading and extracting reveal.js  (but speaker notes will not work):

~~~
pandoc -t revealjs --variable=revealjs-url:http://lab.hakim.se/reveal-js workshop-PAF.md --self-contained --standalone -o /tmp/paf.html
~~~

## PDF output with pandoc

~~~
pandoc workshop-PAF.md -o /tmp/paf.pdf
~~~
