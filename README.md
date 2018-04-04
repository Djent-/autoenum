# autoenum
Script written in Perl to automate network scans.

How to use
==========

Take your list of IP addresses and put them in a file, one per line. You can also use CIDR notation.

If you're running `autoenum.pl` on a hosted server (recommended), swap `$ISLOCAL` on [line 19](https://github.com/Djent-/autoenum/blob/master/autoenum.pl#L19) to `0`.

```
autoenum.pl [filename]
```

Use Case
========

Based on a true story: You have 32 hours for an external network assessment. There are 50 IPs to test and you want to know as much about them as possible.

About
=====

This uses masscan for faster port enumeration. Running from a hosted server is recommended.

Check out the script options on lines 18, and 19.

You need the following installed and accessible through your $PATH:
 - masscan
 - nmap
 - theHarvester.py
 - firefox

What happens:
 - masscan
 - nmap
 - FireFox to screenshot
 - theHarvester
 - FireFox to screenshot discovered subdomains
 - ...
 - You get a nice report!

Can I use this for internal IP addresses?
-----

A: Yes. theHarvester won't like it, but it will still work. The point of running masscan from a hosted server is that you can get it going blazing fast without melting your local network. Try editing the masscan command being run on line 35 to test all 65535 ports and up the rate *a bit*.

What do I do if masscan 'waiting' goes negative?
-----

A: `sudo pkill sudo` [I don't know why this happens](https://github.com/robertdavidgraham/masscan/issues/144), so you'll need to fallback to older methods if you experience it. This issue depends on the ports/IPs scanned. Compiling masscan with glibc [might fix it](https://github.com/r0p0s3c/masscan/commit/667222151f13338d58a6b07d37035053cdb5d03f).
