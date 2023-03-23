#lang setup/infotab

(define name "cover-coveralls")
(define collection 'multi)

(define version "0.1")

(define deps '(("base" #:version "6.1.1") "cover-lib"))

(define build-deps '("rackunit-lib"))
