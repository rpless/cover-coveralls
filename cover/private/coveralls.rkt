#lang racket/base
(provide generate-coveralls-coverage)
(require json
         racket/file
         racket/function
         racket/list
         racket/port
         racket/pretty
         racket/runtime-path
         racket/string
         racket/system
         cover/private/file-utils)


(module+ test
  (require rackunit cover racket/runtime-path)
  (require (for-syntax racket/base))
  (define-runtime-path tests/prog.rkt "tests/prog.rkt")
  (define-runtime-path root "..")

  (define-syntax (with-env stx)
    (syntax-case stx ()
      [(test-with-env (env ...) test ...)
       #'(parameterize ([current-environment-variables
                         (make-environment-variables
                          (string->bytes/utf-8 env) ...)])
           test ...)])))

;; Coveralls

;; Maps service name to the environment variable that indicates that the service is to be used.
(define BUILD-TYPES (hash "travis-ci" "TRAVIS_JOB_ID"))

;; Coverage [path-string] -> Void
(define-runtime-path post "curl.sh")
(define (generate-coveralls-coverage coverage files [dir "coverage"])
  (send-coveralls-info (generate-and-save-data coverage files dir)))

(define (generate-and-save-data coverage files dir)
  (make-directory* dir)
  (define coverage-path dir)
  (define coverage-file (build-path coverage-path "coverage.json"))
  (define data (generate-coveralls-report coverage files))
  (vprintf "writing json to file ~s\n" coverage-file)
  (with-output-to-file coverage-file
    (thunk (write-json data))
    #:exists 'replace)
  (vprintf "data written was:\n")
  (vprintf #:formatter pretty-format data)
  coverage-file)

(module+ test
  (test-begin
   (with-env ("COVERALLS_REPO_TOKEN" "abc")
     (define temp-dir (make-temporary-file "covertmp~a" 'directory))
     (test-files! tests/prog.rkt)
     (define coverage (get-test-coverage))
     (define data-file (generate-and-save-data coverage (list (->absolute tests/prog.rkt)) temp-dir))
     (define rfile (build-path temp-dir "coverage.json"))
     (check-equal? data-file rfile)
     (check-true (file-exists? rfile)))))

(define (send-coveralls-info coverage-file)
  (vprintf "invoking coveralls API")
  (define curl-output (open-output-string))
  (parameterize ([current-output-port curl-output])
    (define result
      (system* (path->string post) coverage-file "-v"))
    (vprintf (get-output-string curl-output))
    (unless result
      (error 'coveralls "request to coveralls failed"))))

(define (generate-coveralls-report coverage files)
  (define json (generate-source-files coverage files))
  (define build-type (determine-build-type))
  (define git-info (get-git-info))
  (hash-merge json (hash-merge build-type git-info)))

(module+ test
  (test-begin
   (parameterize ([current-directory root]
                  [current-cover-environment (make-cover-environment)])
     (define file (path->string (simplify-path tests/prog.rkt)))
     (test-files! (path->string (simplify-path tests/prog.rkt)))
     (define coverage (get-test-coverage))
     (define report
       (with-env ("COVERALLS_REPO_TOKEN" "abc")
         (generate-coveralls-report coverage (list (->absolute file)))))
     (check-equal?
      (hash-ref report 'source_files)
      (list (hasheq 'source (file->string tests/prog.rkt)
                    'coverage (line-coverage coverage file)
                    'name "private/tests/prog.rkt")))
     (check-equal? (hash-ref report 'repo_token) "abc"))))

;; -> [Hasheq String String
;; Determine the type of build (e.g. repo token, travis, etc) and return the appropriate metadata
(define (determine-build-type)
  (define service-name (for/first ([(name var) BUILD-TYPES] #:when (getenv var)) name))
  (define repo-token (getenv "COVERALLS_REPO_TOKEN"))
  (vprintf "using repo token: ~s\n" repo-token)
  (vprintf "using service name: ~s\n" service-name)
  (cond [service-name
         (hasheq 'service_name service-name
                 'service_job_id (getenv (hash-ref BUILD-TYPES service-name))
                 'repo_token repo-token)]
        [repo-token (hasheq 'service_name "cover" 'repo_token repo-token)]
        [else (error "No repo token or ci service detected")]))
(module+ test
  (with-env ()
    (check-exn void determine-build-type))
  (with-env ("COVERALLS_REPO_TOKEN" "abc")
    (check-equal? (determine-build-type)
                  (hasheq 'service_name "cover"
                          'repo_token "abc")))
  (with-env ("TRAVIS_JOB_ID" "abc")
    (check-equal? (determine-build-type)
                  (hasheq 'service_name "travis-ci"
                          'service_job_id "abc"
                          'repo_token #f))))

;; Coverage (Listof PathString) -> JSexpr
;; Generates a string that represents a valid coveralls json_file object
(define (generate-source-files coverage files)
  (define src-files
    (for/list ([file (in-list files)]
               #:when (absolute-path? file))
      (define local-file (path->string (->relative file)))
      (define src (file->string file))
      (define c (line-coverage coverage file))
      (hasheq 'source src 'coverage c 'name local-file)))
  (hasheq 'source_files src-files))

(module+ test
  (test-begin
   (parameterize ([current-directory root]
                  [current-cover-environment (make-cover-environment)])
     (define file (path->string (simplify-path tests/prog.rkt)))
     (test-files! (path->string (simplify-path tests/prog.rkt)))
     (define coverage (get-test-coverage))
     (check-equal?
      (generate-source-files coverage (list file))
      (hasheq 'source_files
              (list (hasheq 'source (file->string tests/prog.rkt)
                            'coverage (line-coverage coverage file)
                            'name "private/tests/prog.rkt")))))))

;; CoverallsCoverage = Nat | json-null

;; Coverage PathString Covered? -> [Listof CoverallsCoverage]
;; Get the line coverage for the file to generate a coverage report
(define (line-coverage coverage file)
  (define covered? (curry coverage file))
  (define split-src (string-split (file->string file) "\n"))
  (define (process-coverage value rst-of-line)
    (case (covered? value)
      ['covered (if (equal? 'uncovered rst-of-line) rst-of-line 'covered)]
      ['uncovered 'uncovered]
      [else rst-of-line]))
  (define (process-coverage-value value)
    (case value
      ['covered 1]
      ['uncovered 0]
      [else (json-null)]))

  (define-values (line-cover _)
    (for/fold ([coverage '()] [count 1]) ([line (in-list split-src)])
      (cond [(zero? (string-length line)) (values (cons (json-null) coverage) (add1 count))]
            [else (define nw-count (+ count (string-length line) 1))
                  (define all-covered (foldr process-coverage 'irrelevant (range count nw-count)))
                  (values (cons (process-coverage-value all-covered) coverage) nw-count)])))
  (reverse line-cover))

(module+ test
  (define-runtime-path path "tests/not-run.rkt")
  (let ()
    (parameterize ([current-cover-environment (make-cover-environment)])
      (define file (path->string (simplify-path path)))
      (test-files! file)
      (check-equal? (line-coverage (get-test-coverage) file) '(1 0)))))

(define (hash-merge h1 h2) (for/fold ([res h1]) ([(k v) h2]) (hash-set res k v)))

(module+ test
  (let ()
    (check-equal? (hash-merge (hash 'foo 3 'bar 5) (hash 'baz 6))
                  (hash 'foo 3 'bar 5 'baz 6))))


;; Git Magic

(define (get-git-info)
  (hasheq 'git
          (hasheq 'head (get-git-commit)
                  'branch (get-git-branch)
                  'remotes (get-git-remotes))))

(define (get-git-branch)
  (string-trim
   (or (getenv "TRAVIS_BRANCH")
       (with-output-to-string (thunk (system "git rev-parse --abbrev-ref HEAD"))))))

(define (get-git-remotes)
  (parse-git-remote (with-output-to-string (thunk (system "git remote -v")))))
(define (parse-git-remote raw)
  (define lines (string-split raw "\n"))
  (define fetch-only (filter (λ (line) (regexp-match #rx"\\(fetch\\)" line)) lines))
  (for/list ([line (in-list fetch-only)])
    (define split (string-split line))
    (hasheq 'name (list-ref split 0)
            'url (list-ref split 1))))
(module+ test
  (test-begin
   (define raw
     "origin	git@github.com:florence/cover.git (fetch)\norigin	git@github.com:florence/cover.git (push)")
   (check-equal? (parse-git-remote raw)
                 (list (hasheq 'name "origin"
                               'url "git@github.com:florence/cover.git")))))

(define (get-git-commit)
  (define format (string-join '("%H" "%aN" "%ae" "%cN" "%ce" "%s") "%n"))
  (define command (string-append "git --no-pager log -1 --pretty=format:" format))
  (define log (with-output-to-string (thunk (system command))))
  (define lines (string-split log "\n"))
  (for/hasheq ([field (in-list '(id author_name author_email committer_name committer_email message))]
               [line (in-list lines)])
    (values field line)))

;; Util

(define (vprintf #:formatter [format format] . a)
 (log-message (current-logger)
              'debug
              'cover
              (apply format a)
              #f))
