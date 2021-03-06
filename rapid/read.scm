;;; Rapid Scheme --- An R7RS compatible reader with source locations

;; Copyright (C) 2016 Marc Nieper-Wißkirchen

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Locations

(define-record-type source-location-type
  (make-source-location source start end)
  source-location?
  (source source-location-source)
  (start source-location-start)
  (end source-location-end))

(define (make-position line column) (vector line column))
(define (position-line position) (vector-ref position 0))
(define (position-column position) (vector-ref position 1))
(define (source-location-start-line source-location)
  (position-line (source-location-start source-location)))
(define (source-location-start-column source-location)
  (position-column (source-location-start source-location)))
(define (source-location-end-line source-location)
  (position-line (source-location-end source-location)))
(define (source-location-end-column source-location)
  (position-column (source-location-end source-location)))

;;; Ports

(define-record-type source-port-type
  (%make-source-port port source ci? line column)
  source-port?
  (port source-port-port)
  (source source-port-source)
  (ci? source-port-ci? source-port-set-ci!)
  (line source-port-line source-port-set-line!)
  (column source-port-column source-port-set-column!))

(define (make-source-port port source ci?)
  (%make-source-port port source ci? 1 0))

(define (source-port-peek-char source-port)
  (peek-char (source-port-port source-port)))

(define (source-port-read-char source-port)
  (let ((char (read-char (source-port-port source-port))))
    (cond
     ((eof-object? char) char)
     (else
      (case char
	((#\tab)
	 (source-port-set-column! source-port
				  (* (+ (quotient (source-port-column source-port) 8) 1) 8)))
	((#\newline)
	 (source-port-set-column! source-port 0)
	 (source-port-set-line! source-port (+ (source-port-line source-port) 1)))
	((#\return)
	 (source-port-set-column! source-port 0))
	(else
	 (source-port-set-column! source-port (+ (source-port-column source-port) 1))))
      char))))

(define (source-port-fold-case! source-port)
  (source-port-set-ci! source-port #t))

(define (source-port-no-fold-case! source-port)
  (source-port-set-ci! source-port #f))

(define (source-port-position source-port)
  (make-position (source-port-line source-port) (source-port-column source-port)))

(define (source-port-make-location source-port start end)
  (make-source-location (source-port-source source-port) start end))

;;; Reader errors
(define-record-type read-error-object-type
  (make-read-error-object message location)
  read-error-object?
  (message read-error-object-message)
  (location read-error-object-location))

(define (read-error message location)
  (raise (make-read-error-object message location)))

(define (locate-file filename syntax)
  (cond
   ((and syntax (syntax-source-location syntax))
    => (lambda (source-location)
	 (path-join (path-directory (source-location-source source-location))
		    filename)))
   (else
    filename)))

(define (read-file source ci? syntax)
  (make-coroutine-generator
   (lambda (yield)
     (call-with-input-file source
       (lambda (port)
	 (define source-port (make-source-port port source ci?))
	 (let loop ()
	   (define datum-syntax (read-syntax source-port syntax))
	   (unless (eof-object? datum-syntax)
	     (yield datum-syntax)
	     (loop))))))))

;;; The parser itself

;;; XXX: Positions may not yet work correctly. Simplify code below.

(define (read-syntax source-port context)
  (define (read) (source-port-read-char source-port))
  (define (peek) (source-port-peek-char source-port))
  (define (position) (source-port-position source-port))
  (define (make-location start end) (source-port-make-location source-port start end))
  (define (make-syntax datum start end)
    (syntax-make-syntax datum (make-location start end) context #f))
  (define (syntax-start syntax) (source-location-start (syntax-source-location syntax)))
  (define (syntax-end syntax) (source-location-end (syntax-source-location syntax)))
  (define (error message start end) (read-error message (make-location start end)))
  (define start (position))
  (define seen? #f)
  (define (seen!) (set! seen? #t))
  (define (set-start!) (unless seen? (set! start (position))))
  (define (fold-case?) (source-port-ci? source-port))
  (define (maybe-foldcase string)
    (if (fold-case?) (string-foldcase string) string))
  (define (read-token)
    (list->string (let loop ()
		    (define c (peek))
		    (case c
		      ((#\space #\tab #\newline #\return #\| #\( #\) #\" #\;) '())
		      (else
		       (read)
		       (if (eof-object? c)
			   '()
			   (cons c (loop))))))))
  (define (read-inline-hex-escape)
    (define string
      (let loop ()
	(define c (read))
	(when (eof-object? c) (unexpected-end-of-file-error))
	(if (char=? c #\;)
	    '()
	    (cons c (loop)))))
    (integer->char (hex-scalar-value (list->string string) start)))
  (define (skip-intraline-white-space!)
    (let loop ()
      (case (peek)
	((#\space #\tab)
	 (read)
	 (loop)))))
  (define (skip-newline-after-return!)
    (when (eq? (peek) #\newline)
      (read)))
  (define (string->identifier string)
    (define (letter? c)
      (or (char<=? #\A c #\Z) (char<=? #\a c #\z)))
    (define (special-initial? c)
      (and (member c '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~ #\@) char=?)
	   #t))
    (define (initial? c)
      (or (letter? c) (special-initial? c)))
    (define (digit? c)
      (char<=? #\0 c #\9))
    (define (special-subsequent? c)
      (or (explicit-sign? c) (char=? c #\.) (char=? c #\@)))
    (define (subsequent? c)
      (or (initial? c) (digit? c) (special-subsequent? c)))
    (define (explicit-sign? c)
      (or (char=? c #\+) (char=? c #\-)))
    (define (dot-subsequent? c)
      (or (sign-subsequent? c) (char=? c #\.)))
    (define (sign-subsequent? c)
      (or (initial? c) (explicit-sign? c) (char=? c #\@)))
    (define (identifier)
      (string->symbol (maybe-foldcase string)))
    (define n (string-length string))
    (define (parse-subsequent i)
      (if (>= i n)
	  (identifier)
	  (and (subsequent? (string-ref string i))
	       (parse-subsequent (+ i 1)))))
    (and
     (> n 0)
     (let ((c (string-ref string 0)))
       (cond
	((initial? c)
	 (parse-subsequent 1))
	((explicit-sign? c)
	 (if (= n 1)
	     (identifier)
	     (cond
	      ((sign-subsequent? (string-ref string 1))
	       (parse-subsequent 2))
	      ((char=? (string-ref string 1) #\.)
	       (and (>= n 3)
		    (dot-subsequent? (string-ref string 2))
		    (parse-subsequent 3)))
	      ((char=? c #\.)
	       (and (dot-subsequent? (string-ref string 1))
		    (parse-subsequent 2)))
	      (else #f))))
	((and (char=? c #\.) (>= n 1) (dot-subsequent? (string-ref string 1)))
	 (parse-subsequent 2))
	(else #f)))))
  (define (read-string delimiter)
    (define list
      (let loop ()
	(let ((start (position)))
	  (define c (read))
	  (when (eof-object? c) (unexpected-end-of-file-error))
	  (case c
	    ((#\return)
	     (skip-newline-after-return!)
	     (cons #\newline (loop)))
	    ((#\\)
	     (when (eof-object? c) (unexpected-end-of-file-error))
	     (let ((c (read)))
	       (cond
		((assoc c escape-sequences char=?)
		 => (lambda (escape-sequence)
		      (cons (cdr escape-sequence) (loop))))
		((char=? c #\x)
		 (let ((c (read-inline-hex-escape)))
		   (cons c (loop))))
		((member c '(#\space #\tab #\newline #\return) char=?)
		 (when (eq? delimiter #\|)
		   (error "bad escape sequence" start (position)))
		 (skip-intraline-white-space!)
		 (case (peek)
		   ((#\newline) (read))
		   ((#\return)
		    (skip-newline-after-return!))
		   (else
		    (error "line ending expected" start (position))))
		 (skip-intraline-white-space!)
		 (loop))
		(else
		 (error "bad escape sequence" start (position))))))
	    (else
	     (if (char=? c delimiter) '() (cons c (loop))))))))
    (list->string list))
  (define (hex-scalar-value string start)  ;; TODO: let start point to the individual problem
    (define n (string-length string))
    (unless (> n 0)
      (error "bad hex scalar value" start (position)))
    (let loop ((i 0) (value 0))
      (if (= i n)
	  value
	  (let* ((n (char->integer (string-ref string i)))
		 (d (cond
		     ((and (>= n #x30) (<= n #x39)) (- n #x30))
		     ((and (>= n #x41) (<= n #x46)) (- n (- #x41 10)))
		     ((and (>= n #x61) (<= n #x66)) (- n (- #x61 10)))
		     (else (error "invalid hex digit" start (position))))))
	    (loop (+ i 1) (+ (* value 16) d))))))
  (define (digit-value char)
    (and (char<=? #\0 char #\9) (- (char->integer char) #x30)))
  (define character-names '
    (("alarm" . #\alarm)
     ("backspace" . #\backspace)
     ("delete" . #\delete)
     ("escape" . #\escape)
     ("newline" . #\newline)
     ("null" . #\null)
     ("return" . #\return)
     ("space" . #\space)
     ("tab" . #\tab)))
  (define escape-sequences '
    ((#\a . #\alarm)
     (#\b . #\backspace)
     (#\t . #\tab)
     (#\n . #\newline)
     (#\r . #\return)
     (#\" . #\")
     (#\\ . #\\)
     (#\| . #\|)))
  (define references (make-table (make-eq-comparator)))
  (define declarations '())
  (define-record-type reference-type  ;; XXX Find better name for reference
    (%make-reference uses) reference? (uses reference-uses reference-set-uses!))
  (define (make-reference) (%make-reference '()))
  (define (unexpected-end-of-file-error)
    (error "unexpected end of file" (position) (position)))
  (define syntax
    (let %read-syntax ((allowed-tokens '(eof-object)))
      (define start (position))
      (define (read-syntax) (%read-syntax allowed-tokens))
      (define (abbreviation identifier start)  ;; MOVE OUT
	(define syntax (make-syntax identifier start (position)))
	(define datum-syntax (read-syntax))
	(make-syntax (list syntax datum-syntax) start (position)))
      (define c (peek))
      (if
       (eof-object? c)
       (if (memq 'eof-object allowed-tokens)
	   c
	   (unexpected-end-of-file-error))
       (case c
	 ;; Whitespace
	 ((#\space #\tab #\newline #\return)
	  (read)
	  (set-start!)
	  (read-syntax))
	 ;; Line comment
	 ((#\;)
	  (read)
	  (let loop ()
	    (define c (read))
	    (unless (or (eof-object? c) (char=? c #\return) (char=? c #\newline))
	      (loop)))
	  (set-start!)
	  (read-syntax))
	 ;; List
	 ((#\()
	  (let ((start (position)))
	    (read)
	    (let loop ((datum* '())) ;; TODO rename datum* -> syntax* because it is syntax
	      (define datum (%read-syntax '(closing-parenthesis dot)))
	      (case datum
		((closing-parenthesis)
		 (make-syntax (reverse datum*) start (position)))
		((dot)
		 (let* ((dot-position
			 (position))
			(dotted-list
			 (let* ((rest (%read-syntax '())) (datum (syntax-datum rest)))
			   (append (reverse datum*)
				   (if (or (list? datum) (null? datum))
				       datum
				       rest)))))
		   (case (%read-syntax '(closing-parenthesis))
		     ((closing-parenthesis)
		      (make-syntax dotted-list start (position)))
		     (else
		      (error "expected end of list after dot" dot-position (position))))))
		(else (loop (cons datum datum*)))))))
	 ;; Quote
	 ((#\')
	  (let ((start (position)))
	    (read)
	    (abbreviation 'quote start)))
	 ;; Quasiquote
	 ((#\`)
	  (let ((start (position)))
	    (read)
	    (abbreviation 'quasiquote start)))
	 ;; Unquote
	 ((#\,)
	  (let ((start (position)))
	    (read)
	    (cond
	     ((char=? (peek) #\@)
	      (read)
	      (abbreviation 'unquote-splicing start))
	     (else
	      (abbreviation 'unquote start)))))
	 ;; Closing parenthesis
	 ((#\))
	  (let ((start (position)))
	    (read)
	    (if (memq 'closing-parenthesis allowed-tokens)
		'closing-parenthesis
		(error "too many ')'s" start (position)))))
	 ;; Sharp token
	 ((#\#)
	  ;; Eat sharp
	  (let ((start (position)))
	    (read)
	    (when (eof-object? (peek)) (unexpected-end-of-file-error))
	    (case (peek)
	      ;; Datum comment
	      ((#\;)
	       (read)
	       (read-syntax)
	       (set-start!)
	       (read-syntax))
	      ;; Nested comment
	      ((#\|)
	       (read)
	       (let loop ((level 1))
		 (when (> level 0)
		   (let ((c (read)))
		     (when (eof-object? c) (unexpected-end-of-file-error))
		     (let ((s (string c (peek))))
		       (cond
			((string=? s "#|")
			 (read)
			 (loop (+ level 1)))
			((string=? s "|#")
			 (read)
			 (loop (- level 1)))
			(else
			 (loop level)))))))
	       (set-start!)
	       (read-syntax))
	      ;; Directive
	      ((#\!)
	       (read)
	       (let ((token (read-token)))
		 (cond
		  ((string-ci=? token "fold-case")
		   (source-port-fold-case! #t))
		  ((string-ci=? token "no-fold-case")
		   (source-port-no-fold-case! #f))
		  (else
		   (error "invalid directive" start (position))))
		 (set-start!)
		 (read-token)))
	      ;; Boolean
	      ((#\t #\f #\T #\F)
	       (seen!)
	       (let ((token (read-token)))
		 (cond
		  ((or (string-ci=? token "t") (string-ci=? token "true"))
		   (make-syntax #t start (position)))
		  ((or (string-ci=? token "f") (string-ci=? token "false"))
		   (make-syntax #f start (position)))
		  (else (error "invalid constant" start (position))))))
	      ;; Character
	      ((#\\)
	       (seen!)
	       (read)
	       (let ((token (read-token)))
		 (define n (string-length token))
		 (case n
		   ((0)
		    (let ((c (read)))
		      (when (eof-object? c)
			(unexpected-end-of-file-error))
		      (make-syntax c start (position))))
		   ((1)
		    ;; Any character
		    (make-syntax (string-ref token 0) start (position)))
		   (else
		    (cond
		     ;; Character name
		     ((assoc token character-names (if (fold-case?) string-ci=? string=?))
		      => (lambda (character-name)
			   (make-syntax (cdr character-name) start (position))))
		     (else
		      (unless (char=? (string-ref token 0) #\x)
			(error "bad character" start (position)))
		      ;; Hex scalar value
		      (make-syntax (integer->char (hex-scalar-value (string-copy token 1) start))
				   start (position))))))))
	      ;; Vector
	      ((#\()
	       (seen!)
	       (read)
	       (let loop ((datum* '()))
		 (define datum (%read-syntax '(closing-parenthesis)))
		 (case datum
		   ((closing-parenthesis)
		    (make-syntax (list->vector (reverse datum*)) start (position)))
		   (else (loop (cons datum datum*))))))
	      ;; Bytevector
	      ((#\u)
	       (seen!)
	       (unless (string-ci=? (read-token) "u8")
		 (error "invalid sharp token" start (position)))
	       (unless (char=? (peek) #\()
		 (error "'(' expected" start (position)))
	       ;; Eat opening parenthesis
	       (read)
	       (let loop ((byte* '()))
		 (define datum (%read-syntax '(closing-parenthesis)))
		 (case datum
		   ((closing-parenthesis)
		    (make-syntax (apply bytevector (reverse byte*)) start (position)))
		   (else
		    (let ((byte (syntax-datum datum)))
		      (unless (and (exact-integer? byte) (<= 0 byte 255))
			(error "not a byte " (syntax-start datum) (syntax-end datum)))
		      (loop (cons byte byte*)))))))
	      ((#\e #\i #\d #\b #\o #\x)
	       (seen!)
	       (cond
		((string->number (string-append "#" (read-token)))
		 => (lambda (number)
		      (make-syntax number start (position))))
		(else (error "bad number" start (position)))))
	      (else
	       (seen!)
	       (unless (digit-value (peek))
		 (error "invalid sharp syntax" start (position)))
	       (let ((label (let loop ((value 0))
			      (define c (peek))
			      (cond
			       ((digit-value c)
				=> (lambda (n)
				     (read)
				     (loop (+ (* 10 value) n))))
			       (else value)))))
		 (case (peek)
		   ;; Datum label
		   ((#\=)
		    ;; Eat =
		    (read)
		    (let ()
		      (define reference (make-reference))
		      (define declaration (cons #f reference))
		      (table-set! references label reference)
		      (set! declarations (cons declaration declarations))
		      (let ((syntax (%read-syntax '())))
			(set-car! declaration syntax)
			syntax)))
		   ;; Datum reference
		   ((#\#)
		    ;; Eat #
		    (read)
		    (let ()
		      (define (unknown-reference-error)
			(error "unknown reference" start (position)))
		      (define reference (table-ref references label unknown-reference-error))
		      (define syntax (make-syntax reference start (position)))
		      (reference-set-uses! reference (cons syntax (reference-uses reference)))
		      syntax))
		   (else (error "bad label datum" start (position)))))))))
	 ((#\")
	  (seen!)
	  (read)
	  (let ((string (read-string #\")))
	    (make-syntax string start (position))))
	 ((#\|)
	  (seen!)
	  (read)
	  (let ((identifier (string->symbol (maybe-foldcase (read-string #\|)))))
	    (make-syntax identifier start (position))))
	 (else
	  (seen!)
	  (let ((token (read-token)))
	    (cond
	     ((string=? token ".")
	      (read)
	      (if (memq 'dot allowed-tokens)
		  'dot
		  (error "unexpected '.'" start (position))))
	     ((string->number token)
	      => (lambda (number)
		   (make-syntax number start (position))))
	     ((string->identifier token)
	      => (lambda (identifier)
		   (make-syntax identifier start (position))))
	     (else
	      (error "bad token" start (position))))))))))
  ;; Body
  (let loop ((declarations declarations))
    (if (null? declarations)
	;; Return fully patched syntax object
	syntax
	;; Patch
	(let* ((syntax (caar declarations))
	       (datum (syntax-datum syntax))
	       (reference (cdar declarations))
	       (declarations (cdr declarations)))
	  (cond
	   ((reference? datum)
	    (when (eq? reference datum)
	      (error "self label reference" (syntax-start syntax) (syntax-end syntax)))
	    (reference-set-uses! datum (append (reference-uses reference)
					       (reference-uses datum))))
	   (else
	    (for-each (lambda (use)
			(syntax-set-datum! use datum))
		      (reference-uses reference))))
	  (loop declarations)))))
