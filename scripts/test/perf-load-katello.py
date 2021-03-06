#!/usr/bin/python

import datetime
import time
import optparse
import string
import logging
import threading
import sys
import os
import random
import httplib
from urlparse import urlparse
import urllib2
import time
from optparse import OptionParser

from multiprocessing import Process
from multiprocessing import Pool


def randomString():
    # The characters to make up the random password
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for x in range(random.randint(8, 16)))     

ENVIRONMENTS = ["DEV", "TEST", "STAGE", "PROD"]

def hit_url_ab(hits, cookie, concurrency, url):
    #  ab  -n 10 -C "_src_session=BAh7CSIQX2NzcmZfW..snip..b9c7f05ccd78027" "http://0.0.0.0:3000/dashboard"
    retval = os.system("ab -n %s -C \"%s\" -c %s %s" % (hits, cookie, concurrency, url))
    
def hit_url(hits, cookie, url):
    o = urlparse(url)
    
    conn = httplib.HTTPSConnection(o.netloc)
    headers = {'Cookie': cookie,
               'User-Agent': 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'}
    
    
    for i in range(hits):
        start = time.time()    
        request = urllib2.Request(url)
        request.add_header('User-Agent', 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)')
        request.add_header('Cookie', cookie) 
        response = urllib2.urlopen(request)
        data = response.read()
        end = time.time()
        elapsed = end - start
        print "  code: %s for : [%s], time: [%s]" % (response.code, url, elapsed)


        
    

if __name__ == '__main__':
 
    parser = OptionParser("usage: %prog [options]")
    parser.add_option('--hits',  dest='hits',  
                        help="Number of hits to each url in the url list", type="int", 
                        default=1)
    parser.add_option('--rooturl',  dest='rooturl',  
                        help="Root URL of the website you want to hit, eg: https://0.0.0.0:3000", 
                        default="https://0.0.0.0:3000")
    parser.add_option('--cookie',  dest='cookie',  
                        help="Cookie value from your logged in browser, eg: _src_session=BAh7CSIQX2NzcmZfW..snip..b9c7f05ccd78027", 
                        default=None)
    parser.add_option('--pathlist',  dest='pathlist',  
                        help="File containing list of paths (not including hostname) you wish to hit with newline for each path.  eg: /dashboard", 
                        default='./url-list.txt')
    parser.add_option('--concurrency',  dest='concurrency',  
                        help="Number of concurrent threads Apache Bench starts up", type="int", 
                        default=1)

    (options, args) = parser.parse_args(sys.argv[1:])
    
    if not options.cookie:
        sys.exit("ERROR: You must specify a cookie value from your logged in browser, eg: _src_session=BAh7CSIQX2NzcmZfW..snip..b9c7f05ccd78027")
    
    f = open(options.pathlist, 'r')
    lines = f.readlines()
    threads = []
    for i in range(len(lines)):
        full_url = (options.rooturl + lines[i]).rstrip('\n')
        concurrency_per_url = int(options.concurrency)
        for z in range(concurrency_per_url):
            print "Starting thread# [%s] for: [%s] " % (z, full_url)
            p = Process(target=hit_url, args=(options.hits, options.cookie, full_url))
            p.start()
            threads.append(p)
    for p in threads:
        p.join()
