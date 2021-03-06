;;; Rapid Scheme --- An R7RS reader with source information

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

(define-library (rapid error)
  (export compile-error-object?
	  compile-error
	  compile-warning
	  compile-note
	  compile-error?
	  compile-warning?
	  display-compile-error
	  guard-compile)
  (import (scheme base)
	  (scheme process-context)
	  (scheme write)
	  (rapid and-let)
	  (rapid boxes)
	  (rapid syntax)
	  (rapid read))
  (include "error.scm"))
