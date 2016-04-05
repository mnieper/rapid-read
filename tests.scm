(import (scheme base)
	(rapid test)
	(rename (rapid syntax test) (run-tests run-rapid-syntax-tests))
	(rename (rapid read test) (run-tests run-rapid-read-tests)))

(test-begin "Rapid Read")

(run-rapid-syntax-tests)
(run-rapid-read-tests)

(test-end "Rapid Read")
