;;; Rapid Scheme --- A R7RS compatible reader with source locations

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

(define-record-type <syntax>
  (make-syntax datum source-location context aux)
  syntax?
  (datum syntax-datum syntax-set-datum!)
  (source-location syntax-source-location)
  (context syntax-context syntax-set-context!)
  (aux syntax-aux syntax-set-aux!))

(define syntax->datum
  (case-lambda
   ((syntax) (syntax->datum syntax (lambda (datum) datum)))
   ((syntax proc)
    (define syntax-stack '())
    (define (push-syntax! syntax) (set! syntax-stack (cons syntax syntax-stack)))
    (define datum
      (let syntax->datum ((syntax syntax))
	(cond
	 ((syntax-aux syntax) => (lambda (datum) datum))
	 (else
	  (let ((datum (syntax-datum syntax)))
	    (cond
	     ((vector? datum)
	      (push-syntax! syntax)
	      (let* ((n (vector-length datum))
		     (vector (make-vector n)))
		(syntax-set-aux! syntax vector)
		(do ((i 0 (+ i 1)))
		    ((>= i n))
		  (vector-set! vector i (syntax->datum (vector-ref datum i)))) 
		vector))
	     ((pair? datum)
	      (push-syntax! syntax)
	      (let* ((pair (list #f)))
		(syntax-set-aux! syntax pair)
		(set-car! pair (syntax->datum (car datum)))
		(do ((datum datum (cdr datum)) (pair pair (cdr pair)))
		    ((not (pair? (cdr datum)))
		     (unless (null? (cdr datum))
		       (set-cdr! pair (syntax->datum (cdr datum)))))
		  (set-cdr! pair (list (syntax->datum (cadr datum)))))		
		pair))
	     (else
	      (proc datum))))))))
    (for-each
     (lambda (syntax)
       (syntax-set-aux! syntax #f))
     syntax-stack)
    datum)))

(define derive-syntax
  (case-lambda
   ((datum syntax)
    (derive-syntax datum syntax (syntax-context syntax)))
   ((datum syntax context)
    (make-syntax datum (syntax-source-location syntax) context #f))))

(define (%datum->syntax datum syntax)
  (if syntax
      (derive-syntax datum syntax)
      (make-syntax datum #f #f #f)))

;; XXX: Merge with derive-syntax?
(define datum->syntax
  (case-lambda
   ((datum) (datum->syntax datum #f))
   ((datum syntax)
    (let loop ((datum datum))
      ;; TODO: Handle vectors, improper lists, circular literals
      (cond
       ((syntax? datum) datum)
       ((list? datum) (%datum->syntax (map loop datum) syntax))
       (else
	(%datum->syntax datum syntax)))))))
