;;; gijit-3.92
;;;
;;; (Setq *gijit-version-string* "3.92") ; update this below when changing.
;;;
;;; gijit.el     - is a pair of modes for sending lines from a 
;;;                  script (sender) to a comint-started inferior 
;;;                  (receiver) process. We  use Ctrl-n by default as 
;;;                  the "send this line and step" key. This enables 
;;;                  one to step through scripts easily when working
;;;                  with an interpreter, such as gi for Go, Pure, R, Haskell,
;;;                  shell, Python, and so forth. Functions for
;;;                  stepping through s-expressions for Lisp and 
;;;                  Scheme work are also available. This file is
;;;                  by default setup for gi, a go interpreter.
;;;
;;; License:      This minimal pair of (major and inferior) modes
;;;               was derived from the Emacs Octave Support modes in 
;;;               octave-mod.el and octave-inf.el, with a little help 
;;;               (and alot of inspiration) from the ess-mode.el for
;;;               R. As such it falls under the GNU General Public
;;;               License version 3 or later.
;;;
;;; Copyright (C) 2018, Author: Jason E. Aten, Ph.D.
;;;
;;; how to install:
;;;
;;; (1) If you are changing which interpreter you want to use, examine
;;;     and adjust the "commonly-adjusted parameters" section just below.
;;;
;;; (2) Copy gijit.el into your ~/.emacs.d/  directory.
;;;
;;; (3) Then put this in your .emacs:
;;;
;;;    (load "/home/yourHomeDirectory/.emacs.d/gijit.el") ; adjust path to fit your home directory.
;;;    (require 'gijit-mode)
;;;    (global-set-key "\C-n" 'gijit-send-line)
;;;
;;; (4) Optionally for speed, M-x byte-compile-file <enter> 
;;;                           ~/.emacs.d/gijit.el <enter>
;;;
;;; (5) To use, do 'M-x run-gijit' to start the interpreter. Open
;;;     your script and in the script buffer do 'M-x gijit-mode'.
;;;
;;;     Or, open a file with an automatically recognized extension
;;;     (as specified below) and press 'C-n' on the first line
;;;     you want executed in the interpreter.


;; To over-ride parameters, skip down to the "commonly-adjusted
;; parameters" section below these declarations.
;;
;; Here we just document the typically overriden parameters of interest.
;; NB: these just give defaults, which the setq settings below will override.
;; Putting them here keeps the byte-compiler from complaining.

(defvar *inferior-gijit-program* "gi"
  "Program invoked by `inferior-gijit'.")

(defvar *inferior-gijit-buffer* "*gijit*"
  "*Name of buffer for running an inferior Gijit process.")

(defvar *inferior-gijit-regex-prompt* "[^\(gi>\)\|\(\.\.\.\)]*[gi> ]"
  "Regexp to match prompts for the inferior Gijit process.")
(setq *inferior-gijit-regex-prompt* "[^\(gi>\)\|\(\.\.\.\)]*[gi> ]")

(defvar *gijit-keypress-to-sendline* (kbd "C-n")
  "keypress that, when in a pure mode script, sends a line to the interpreter
   and then steps to the next line.")

(defvar *gijit-keypress-to-send-sexp-jdev*      (kbd "C-9")
  "keypress that sends the next sexp to the repl, and advances past it.")

(defvar *gijit-keypress-to-send-sexp-jdev-prev* (kbd "C-p")
  "keypress that sends the previous sexp to the repl")

(defvar *gijit-version-string* "3.92"
  "version of gijit currently running.")

(defvar *gijit-gdb-terp-buffer* "*vlush2-gdb*"
  "name of the *gdb-terp* buffer when running gdbterp under gijit.")

;; ================================================
;; ================================================
;; begin commonly-adjusted parameters

;; the name of the interpreter to run
(setq *inferior-gijit-program*  "gi")


;; the name of the buffer to run the interpreter in
(setq *inferior-gijit-buffer* "*gijit*")

;; name of the gdb buffer
(setq *gijit-gdb-terp-buffer* "*gdb-terp*")

;; the comment character
(setq *inferior-gijit-comment-char* ";")

(setq  comment-start   *inferior-gijit-comment-char*)
(setq  comment-end     nil)
(setq  comment-column  4)


;; file extensions that indicate we should automatically enter gijit mode...
(setq auto-mode-alist (cons '("\\.go$" . gijit-mode) auto-mode-alist))

;; regexp to know when interpreter output is done and we are at a prompt.
;;(setq *inferior-gijit-regex-prompt*  "[^\]]*: ")

;; keypress that, when in a pure mode script, sends a line to the interpreter
;;  and then steps to the next line.
(setq *gijit-keypress-to-sendline* (kbd "C-n"))

;; keypress that, when in a pure mode script, sends an sexp to the JDEV repl
;;  and then steps to the next line.
(setq *gijit-keypress-to-send-sexp-jdev*      (kbd "C-9"))
(setq *gijit-keypress-to-send-sexp-jdev-prev* (kbd "C-p"))

;; end commonly-adjusted parameters
;; ================================================
;; ================================================


(defvar inferior-gijit-output-list nil)
(defvar inferior-gijit-output-string nil)
(defvar inferior-gijit-receive-in-progress nil)
(defvar inferior-gijit-process nil)

(defvar gijit-mode-hook nil
  "*Hook to be run when Gijit mode is started.")

(defvar gijit-send-show-buffer t
  "*Non-nil means display `*inferior-gijit-buffer*' after sending to it.")
(setq gijit-send-show-buffer t)

(defvar gijit-send-line-auto-forward nil
  "*Control auto-forward after sending to the inferior Gijit process.
Non-nil means always go to the next Gijit code line after sending.")

(setq gijit-send-line-auto-forward nil)

(defvar gijit-send-echo-input t
  "*Non-nil means echo input sent to the inferior Gijit process.")
(setq gijit-send-echo-input t)


;; try to hide the ctrl-M carriage returns that ipython generates.
(defun remove-dos-eol ()
  "Do not show ^M in files containing mixed UNIX and DOS line endings."
  (interactive)
  (with-current-buffer *inferior-gijit-buffer* 
    (setq buffer-display-table (make-display-table))
    (aset buffer-display-table ?\^M [])))


;;; Motion
(defun gijit-next-code-line (&optional arg)
  "Move ARG lines of Gijit code forward (backward if ARG is negative).
Skips past all empty and comment lines.  Default for ARG is 1.

On success, return 0.  Otherwise, go as far as possible and return -1."
  (interactive "p")
  (or arg (setq arg 1))
  (beginning-of-line)
  (let ((n 0)
	(inc (if (> arg 0) 1 -1)))
    (while (and (/= arg 0) (= n 0))
      (setq n (forward-line inc))
      (while (and (= n 0)
		  (looking-at "\\s-*\\($\\|\\s<\\)"))
	(setq n (forward-line inc)))
      (setq arg (- arg inc)))
    n))

(defun gijit-previous-code-line (&optional arg)
  "Move ARG lines of Gijit code backward (forward if ARG is negative).
Skips past all empty and comment lines.  Default for ARG is 1.

On success, return 0.  Otherwise, go as far as possible and return -1."
  (interactive "p")
  (or arg (setq arg 1))
  (gijit-next-code-line (- arg)))


;;; Communication with the inferior Gijit process
(defun gijit-kill-process ()
  "Kill inferior Gijit process and its buffer."
  (interactive)
  (if inferior-gijit-process
      (progn
	(process-send-string inferior-gijit-process "quit;\n")
	(accept-process-output inferior-gijit-process)))
  (if *inferior-gijit-buffer*
      (kill-buffer *inferior-gijit-buffer*)))

(defun gijit-show-process-buffer ()
  "Make sure that `*inferior-gijit-buffer*' is displayed."
  (interactive)
  (if (get-buffer *inferior-gijit-buffer*)
      (display-buffer *inferior-gijit-buffer*)
      ;(display-buffer  *gijit-gdb-terp-buffer*)
    (message "No buffer named %s" *inferior-gijit-buffer*)))

(defun gijit-hide-process-buffer ()
  "Delete all windows that display `*inferior-gijit-buffer*'."
  (interactive)
  (if (get-buffer *inferior-gijit-buffer*)
      (delete-windows-on *inferior-gijit-buffer*)
    (message "No buffer named %s" *inferior-gijit-buffer*)))

(defun gijit-send-region (beg end)
  "Send current region to the inferior Gijit process."
  (interactive "r")
  (inferior-gijit t)
  (let ((proc inferior-gijit-process)
	(string (buffer-substring-no-properties beg end))
	line)
    (if (string-equal string "")
	(setq string "\n"))
    (with-current-buffer *inferior-gijit-buffer* 
      (setq inferior-gijit-output-list nil)
      (while (not (string-equal string ""))
	(if (string-match "\n" string)
	    (setq line (substring string 0 (match-beginning 0))
		  string (substring string (match-end 0)))
	  (setq line string string ""))
	(setq inferior-gijit-receive-in-progress t)
	(inferior-gijit-send-list-and-digest (list (concat line "\n")))
;;	(inferior-gijit-send-list-and-digest (list (concat "%cpaste\n" line "\n--\n")))
	(while inferior-gijit-receive-in-progress
	  (accept-process-output proc))
	(insert-before-markers
	 (mapconcat 'identity
		    (append
		     (if gijit-send-echo-input (list line) (list ""))
		     (mapcar 'inferior-gijit-strip-ctrl-g
			     inferior-gijit-output-list)
		     (list inferior-gijit-output-string))
		    "\n")))))
  (if gijit-send-show-buffer
      (gijit-eob)))
       


;; test out moving the inf buffer to end...
(defun gijit-eob ()
  (interactive)
  (let* ((mywin (display-buffer *inferior-gijit-buffer*))
	 (bl (with-current-buffer *inferior-gijit-buffer*
	       (line-number-at-pos (point-min))))
	 (cl (with-current-buffer *inferior-gijit-buffer*
	       (line-number-at-pos (window-point mywin))))
	 (el (with-current-buffer *inferior-gijit-buffer*
	       (goto-char (point-max))
	       (line-number-at-pos))))
    ;;;(message "bl is %d,    el is %d, cl is %d,  el-cl is %d" bl el cl (- el cl))
    (setq other-window-scroll-buffer (get-buffer *inferior-gijit-buffer*))
    (scroll-other-window (- el cl))
    (with-current-buffer *inferior-gijit-buffer*
      (goto-char (point-max))
      (set-window-point mywin (point-max)))
    (display-buffer *inferior-gijit-buffer*)
    ))




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; the entire point of gijit-mode : to enable the use
;; of gijit-send-line with a single keypress.
;;
(defun gijit-send-line (&optional arg)
  "Send current Gijit code line to the inferior Gijit process.
With positive prefix ARG, send that many lines.
If `gijit-send-line-auto-forward' is non-nil, go to the next unsent
code line."
  (interactive "P")
  (or arg (setq arg 1))
  (if (> arg 0)
      (let (beg end)
	(beginning-of-line)
	(setq beg (point))
	(gijit-next-code-line (- arg 1))
	(end-of-line)
	(setq end (point))
	(if gijit-send-line-auto-forward
	    (gijit-next-code-line 1)
	  (forward-line 1))
	(gijit-send-region beg end))))

;;;;;;; sexp-based version -- hard code in *inferior-gijit-buffer*, and remove SLIME dependencies.

;;;;;;;;;;;  gijit-advance-and-eval-sexp-jdev    and   gijit-advance-and-eval-sexp-jdev-prev


(defun nil-to-point-max (x)
  (if x 
      x 
    (point-max)
))

(defun nil-to-point-min (x)
  (if x 
      x 
    (point-min)
))

(defun skip-lisp-comment-lines ()
  "skip over lines that start with semi-colons before they have another non-whitespace character"
  (interactive)
  (let* ((done-skipping)
	 (startp (point))
	 (nextcomment)
	 (eol)
	 (nextword)
	 )
    ;; 
    ;; if nextcomment < eol and ( nextword > nextcomment or nextword is nil ) then skip to next line

    ;; conversely, if nextword < eol and (nextcomment is nil or nextword < nextcomment) then stop skipping lines
    (while (not done-skipping)
      (setq startp        (point))
      (setq nextcomment   (nil-to-point-max (search-forward *inferior-gijit-comment-char* nil 0 1)))
      (setq eol           (progn (goto-char startp) (nil-to-point-max (search-forward "\n" nil 0 1))))
      (setq nextword      (progn (goto-char startp) (+ (point) (skip-chars-forward "\t ;\n"))))
      
      ;; either stop at the word, or go to the end of line
      (if (< nextword eol)
	  (if (or (< nextword nextcomment)
		  (= (point-max) nextcomment))
	      
	      (progn
		(setq done-skipping t)
		(goto-char nextword)
		)

	    (goto-char eol))
	(progn
	  (when (= nextword eol)
	      (setq done-skipping t) ;; stop if nextword == eol
	      )
	  (goto-char eol)
	  )
	)
      )
    )
  )

(defvar DEBUG_STATUS 'off
  "DEBUG_STATUS controls the DEBUG macro's behavior; legit values are 'on or 'off.")

;(setq DEBUG_STATUS 'on)
(setq DEBUG_STATUS 'off)

(defmacro DEBUG (&rest body)
  "DEBUG is simple call to (@body) or nil, depending on the value of DEBUG_STATUS being 'on or not. 
Makes it easy to debug when needed. You will have to recompile, of course, in order for the
macro to be able to take effect, if you change the value of DEBUG_STATUS. For efficiency's
sake, this is a compile time, not a runtime, convenience."
  (if (eql DEBUG_STATUS 'on)
      `(,@body)
    'nil)
)

;; test
;; (DEBUG message "startp       is %s" startp)
;; (macroexpand '(DEBUG message "startp       is %s" startp))


(defun line-is-comment-or-whitespace ()
  "determine if this line can be ignored because it is just a comment or whitespace"
  (interactive)
  (DEBUG message "***************** starting: (line-is-comment-or-whitespace), at %S" (line-number-at-pos))
  (block block-line-is-comment-or-whitespace
  (let* ((startp (point))
	 (nextword nil)
	 (nextcomment nil)
	 (bol nil)
	 (eol nil)
	 (prevbol nil)
	 )

      (setq startp        (point))
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq prevbol       (progn (goto-char (max (point-min) (- bol 1)))    (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq nextcomment   (progn (goto-char bol)                            (nil-to-point-max (search-forward *inferior-gijit-comment-char* nil 0 1))))
      (setq eol           (progn (goto-char startp)                         (nil-to-point-max (search-forward "\n" nil 0 1))))
      (setq nextword      (progn (goto-char bol)                            (+ (point) (skip-chars-forward "\t ;\n"))))

      (goto-char startp)

      (DEBUG message "startp       is %s" startp)
      (DEBUG message "bol          is %s" bol)
      (DEBUG message "eol          is %s" eol)
      (DEBUG message "prevbol      is %s" prevbol)
      (DEBUG message "nextcomment  is %s" nextcomment)
      (DEBUG message "nextword     is %s" nextword)

      ;; when startp == 1 + bol, and nextcomment == 1 + startp, then we have a line of all comments
      (when (and (= startp (+ 1 bol))
		 (= nextcomment (+ 1 startp)))
	(DEBUG message "line is empty, returning t early")
	(return-from block-line-is-comment-or-whitespace t))

      ;; sanity check for empty lines
      (when (and (= eol (+ 1 startp))
		 (= bol (- startp 1))
		 )
	(progn 
	  (DEBUG message "line is empty, returning t early")
	  (return-from block-line-is-comment-or-whitespace t)))


      ;; if nextword    > eol this is skippable.
      (when (> nextword eol)
	(progn
	  (DEBUG message "nextword > eol, returning t early")
	  (return-from block-line-is-comment-or-whitespace t)))


      ;; INVAR: bol < nextword < eol, only question left: is there a comment before the nextword?

      (if (or (> nextcomment eol)
	      (< nextcomment bol))
	  
	  ;; nextcomment is not in play
	  (progn
	    (DEBUG message "nil: cannot skip b/c bol < nextword < eol, and no comment present on this line.")
	    (return-from block-line-is-comment-or-whitespace nil))
	
	;; INVAR: comment is in play, and may obscucate the entire line.
	(if (<= nextcomment nextword)
	    (progn
	      (DEBUG message "t: can skip")
	      (return-from block-line-is-comment-or-whitespace t))
	  
	  ;;
	  (progn
	    (DEBUG message "nil: cannot skip b/c bol < nextword < nextcomment < eol.")
	    (return-from block-line-is-comment-or-whitespace nil)))

	) ;; endif 
)))


(defun skip-lisp-comment-lines-backwards ()
  "Going backwards, skip over lines that start with semi-colons before they have another non-whitespace character.
The main side-effect is to reposition point. The function returns the new position of point, 
which is just following the next form back."

  (interactive)
  (DEBUG message "***************** starting: (skip-lisp-comment-lines-backwards)")
  (block block-skip-lisp-comment-lines-backwards
    (DEBUG message "--> point is starting at %s" (point))
    (let* ((startp (point))
	   (next-word-back)
	   (bol)
	   (nextcomment)
	   (eol)
	   (start-backwards-search)
	   (starting-line (line-number-at-pos))
	   (cur-line      starting-line)
	   )
      
      ;; back up until we find a line with something like a lisp form on it (and the whole line is not commented out)
      (beginning-of-line)

      ;; handle the case of starting at the beginning of a non-comment line, by backing up one line before we search...
      (when (and (= (point) startp)
		 (> startp  (point-min)))
	;; we started at the beginning of a line, and it's not the first line, so back up past the newline to prev line.
	(goto-char (- startp 1))
	(beginning-of-line))
      
      ;; main backup while loop
      (while (and (line-is-comment-or-whitespace)
		  (> (point) (point-min)))
	(forward-line -1)
	)

      ;; if we have moved lines, reset to our new starting place...
      (setq cur-line (line-number-at-pos))
      (if (= cur-line starting-line)
	  (goto-char startp)
	(progn
	  (end-of-line)
	  (setq startp (point))))
      (DEBUG message "--> After revision of backing up past comments, point is at %s" (point))


      ;; INVAR: we are on a line with some content, or we are at the beginning of the buffer
      (when (line-is-comment-or-whitespace)
	;; beginning of buffer, just get to the start.
	(goto-char (point-min)) 
	(return-from block-skip-lisp-comment-lines-backwards (point-min)))
	  
      (DEBUG message "--> INVAR: we are on a line with some content")
    
      (setq bol           (progn (goto-char startp)                         (nil-to-point-min (search-backward "\n" 0 0 1))))
      (setq nextcomment   (progn (goto-char bol)                            (nil-to-point-max (search-forward *inferior-gijit-comment-char* nil 0 1))))
      (setq eol           (progn (goto-char startp)                         (nil-to-point-max (search-forward "\n" nil 0 1))))

      ;; start from eol, or from nextcomment if nextcomment is < eol
      (setq start-backwards-search eol)
      (when (< nextcomment eol)
	(setq start-backwards-search nextcomment))

      (setq next-word-back 
	    (progn 
	      (goto-char start-backwards-search)    
	      (+ 
	       (point) 
	       (skip-chars-backward "\t ;\n"))))

      (goto-char next-word-back)
)))

;; debug bindings
;;  (global-set-key "\C-o" 'skip-lisp-comment-lines-backwards)
;;  (global-set-key "\C-o" 'line-is-comment-or-whitespace)
;;  (global-set-key "\C-o"   'my-backward-sexp-ignoring-comments)
  (global-set-key "\C-o"   '(forward-line -1))


  
(defun my-forward-sexp-ignoring-comments ()
  "Move forward across one balanced expression (sexp), ignoring ; comments"
  (interactive "^p")

  ;; at end of file? return early
  (if (= (point) (point-max))
      nil
    (progn
      ;; rest of function is in this big else block; we could also do try/catch (maybe later), but this is clearer.
      
      ;; first determine if we are in a comment: iff there is a semi-colon between (point) and previous newline or beginning of buffer
      ;; if we are in a comment, then go to the next line.
      ;; now skip over any additional comments, arriving at the first uncommented sexp
      (setq startp (point))
      
      (search-backward "\n" 0 0 1) ;; side effect is to move point to beginning of line
      (setq bol    (point))
      
      ;; find previous comment
      (goto-char startp) ;; start over
      (search-backward *inferior-gijit-comment-char* 0 0 1) 
      (setq prevcomment (point))
      
      ;; find previous double quote
      (goto-char startp) ;; start over
      (search-backward "\"" 0 0 1)
      (setq prevdoublequote (point))
      
      ;; find end of line
      (search-forward "\n" nil 0 1)
      (setq eol (point))
      (if (not (string= "\n" (buffer-substring startp (+ 1 startp))))
	  (goto-char startp))
      
      ;; rely on the fact that we are now at the beginning of the next line, and check for comments.
      ;; If there is a comment character that is both >= bol and also > prevdoublequote, then skip to next line
      ;; otherwise start over and return to original starting position.
      (unless (and (>= prevcomment bol) (> prevcomment prevdoublequote))
	(goto-char startp))
      
      ;; INVAR: we are at the beginning of a line or at the beginning of a non-commented sexp.
      (skip-lisp-comment-lines) ;; call the above function to handle skipping to the next sexp.
      
      (forward-sexp)
    ;(skip-lisp-comment-lines) ;; get to the beginning of the next form
      )))


(defun my-backward-sexp-ignoring-comments ()
  "Move backward across one balanced expression (sexp), ignoring comments in the form of semicolons"
  (interactive)
  (DEBUG message "******** starting: my-backward-sexp-ignoring-comments")

  ;; at beginning of file? return early
  (if (= (point) (point-min))
      nil
    (progn
      ;; rest of function is in this big else block; we could also do try/catch (maybe later), but this is clearer.

      (skip-lisp-comment-lines-backwards)
      (if (line-is-comment-or-whitespace)
	  (progn
	    (DEBUG message "*************************** my-backward-sexp-ignoring-comments: finishing with (beginning-of-line) and t <<<<<")
	    (beginning-of-line)
	    t)
	(progn
	  (DEBUG message "*************************** my-backward-sexp-ignoring-comments: finishing with (backward-sexp) and t <<<<<")
	  (backward-sexp)
	  t)
	))))


(defun gijit-advance-and-eval-sexp-jdev ()
       "advance one sexp, and copy that sexp into the
*inferior-gijit-buffer*, so as to step through lines in a lisp .cl file"
       (interactive)
       (inferior-gijit t)
       (setq clisp-buf *inferior-gijit-buffer*)
       (setq pstart (point))
       (push-mark)
       (my-forward-sexp-ignoring-comments)
       (setq pend (point))
       (skip-lisp-comment-lines) ;; get to the beginning of the next form, so point is at the beginning of next line.
       ;;(setq str (buffer-substring pstart pend))
       (with-current-buffer clisp-buf (goto-char (point-max)))
       (append-to-buffer clisp-buf pstart pend)
       (with-current-buffer clisp-buf 
	 (setq comint-eol-on-send t)
	 (setq comint-process-echoes nil)
	 (setq comint-move-point-for-output t)
	 (gijit-send-input)
	 (display-buffer clisp-buf)
	 (recenter)
))
	 

(defun gijit-advance-and-eval-sexp-jdev-prev ()
       "copy the previous sexp into the *inferior-gijit-buffer*"
       (interactive)
       (inferior-gijit t)
       (setq clisp-buf *inferior-gijit-buffer*)
       (if (and (my-backward-sexp-ignoring-comments)
		  (not (line-is-comment-or-whitespace)))
	   (progn
	     (setq pstart (point))
	     (push-mark)
	     (forward-sexp)
	     (setq pend (point))
	     (with-current-buffer clisp-buf (goto-char (point-max)))
	     (append-to-buffer clisp-buf pstart pend)
	     (with-current-buffer clisp-buf 
	       (setq comint-eol-on-send t)
	       (setq comint-process-echoes nil)
	       (setq comint-move-point-for-output t)
	       (gijit-send-input)
	       (display-buffer clisp-buf)
	       (recenter)
	       )
	     ;;(skip-lisp-comment-lines)
	     )
	 (beginning-of-line)))


;;;;;;;;;;;; simplest possible major mode stuff

(defvar gijit-mode-map nil
  "Local keymap for gijit mode buffers.")

(setq gijit-mode-map nil)

(if gijit-mode-map
    nil
  (setq gijit-mode-map (make-sparse-keymap))
  (define-key gijit-mode-map *gijit-keypress-to-sendline* 'gijit-send-line)
  (define-key gijit-mode-map *gijit-keypress-to-send-sexp-jdev* 'gijit-advance-and-eval-sexp-jdev)
  (define-key gijit-mode-map *gijit-keypress-to-send-sexp-jdev-prev* 'gijit-advance-and-eval-sexp-jdev-prev)
)

(defun gijit-mode ()
  "simple send-line, aka gijit mode."
  (interactive)
  (kill-all-local-variables)
  (setq major-mode 'gijit-mode)
  (setq mode-name "gijit")
  (use-local-map gijit-mode-map)

  ;; borrow the setup for lisp mode indentation from the other emacs lisp modes.
  (lisp-mode-variables  t)

  (run-mode-hooks 'jdev-mode-hook))


;;; provide ourself

;;;(provide 'gijit-mod)

;;; gijit-mod.el ends here


;;; gijit-inf.el --- running Gijit as an inferior Emacs process

;;(require 'gijit-mod)
(require 'comint)

(defgroup gijit-inferior nil
  "Running Gijit as an inferior Emacs process."
  :group 'gijit)




(defvar inferior-gijit-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map comint-mode-map)
    map)
  "Keymap used in Inferior Gijit mode.")

(defvar inferior-gijit-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\` "w" table)
    table)
  "Syntax table in use in inferior-gijit-mode buffers.")

(defvar inferior-gijit-mode-hook nil
  "*Hook to be run when Inferior Gijit mode is started.")


(defvar *inferior-gijit-startup-args* nil
  "arguments to be given to the Inferior Gijit process on startup.")
;(setq *inferior-gijit-startup-args* (list "console" "--nosep" "--colors=NoColor"))
(setq *inferior-gijit-startup-args* nil) ;;(list "--pylab"))

;;; Compatibility functions
(if (not (fboundp 'comint-line-beginning-position))
    ;; comint-line-beginning-position is defined in Emacs 21
    (defun comint-line-beginning-position ()
      "Returns the buffer position of the beginning of the line, after
any prompt. The prompt is assumed to be any text at the beginning of the 
line matching the regular expression `comint-prompt-regexp', a buffer local 
variable."
      (save-excursion (comint-bol nil) (point))))


(defvar inferior-gijit-output-list nil)
(defvar inferior-gijit-output-string nil)
(defvar inferior-gijit-receive-in-progress nil)
(defvar inferior-gijit-startup-hook nil)


(defun inferior-gijit-mode ()
  "Major mode for interacting with an inferior Gijit process.
Runs Gijit as a subprocess of Emacs, with Gijit I/O through an Emacs
buffer.

Entry to this mode successively runs the hooks `comint-mode-hook' and
`inferior-gijit-mode-hook'."
  (interactive)
  (delay-mode-hooks (comint-mode))
  (setq comint-prompt-regexp *inferior-gijit-regex-prompt*
	major-mode 'inferior-gijit-mode
	mode-name "Inferior Gijit"
	mode-line-process '(":%s"))
  (use-local-map inferior-gijit-mode-map)
  (setq comint-input-ring-file-name
	(or (getenv "GIJIT_HISTFILE") "~/.gijit_hist")
	comint-input-ring-size (or (getenv "GIJIT_HISTSIZE") 1024))
  (comint-read-input-ring t)

  (make-local-variable 'kill-buffer-hook)
  (add-hook 'kill-buffer-hook 'gijit-kill-buffer-function)

  (run-mode-hooks 'inferior-gijit-mode-hook))

;;;###autoload
(defun inferior-gijit (&optional arg)
  "Run an inferior Gijit process, I/O via `*inferior-gijit-buffer*'.
This buffer is put in Inferior Gijit mode.  See `inferior-gijit-mode'.

Unless ARG is non-nil, switches to this buffer.

The elements of the list `*inferior-gijit-startup-args*' are sent as
command line arguments to the inferior Gijit process on startup.

Additional commands to be executed on startup can be provided either in
the file specified by `inferior-gijit-startup-file' or by the default
startup file, `~/.emacs-gijit'."
  (interactive "P")
  (let ((buffer *inferior-gijit-buffer*))
    (get-buffer-create buffer)
    (if (comint-check-proc buffer)
	()
      (with-current-buffer buffer
	(comint-mode)
	(inferior-gijit-startup)
	(inferior-gijit-mode)))
    (if (not arg)
	(pop-to-buffer buffer))))

;;;###autoload
(defalias 'run-gijit 'inferior-gijit)

(defun inferior-gijit-startup ()
  "Start an inferior Gijit process."
  (let ((proc (comint-exec-1
	       (substring *inferior-gijit-buffer* 1 -1)
	       *inferior-gijit-buffer*
	       *inferior-gijit-program*
	       *inferior-gijit-startup-args*)))
    (set-process-filter proc 'inferior-gijit-output-filter)
    (setq comint-ptyp process-connection-type
	  inferior-gijit-process proc
	  inferior-gijit-output-list nil
	  inferior-gijit-output-string nil
	  inferior-gijit-receive-in-progress t)

    (remove-dos-eol)
    (run-hooks 'inferior-gijit-startup-hook)
    (run-hooks 'inferior-gijit-startup-hook)))


(defun inferior-gijit-strip-ctrl-m (string)
  (while (string-match "\r$" string)
      (setq string (concat (substring string 0 (- (length string) 1)) "\n")))
  string)

;; test:
;; (inferior-gijit-strip-ctrl-m "hi")



(defun inferior-gijit-strip-ctrl-g (string)
  "Strip leading `^G' character.
If STRING starts with a `^G', ring the bell and strip it."
  (if (string-match "^\a" string)
      (progn
        (ding)
        (setq string (substring string 1))))
  string)

(defun inferior-gijit-output-filter (proc string)
  "Standard output filter for the inferior Gijit process.
Ring Emacs bell if process output starts with an ASCII bell, and pass
the rest to `comint-output-filter'."
;;  (comint-output-filter proc (inferior-gijit-strip-ctrl-m (inferior-gijit-strip-ctrl-g string))))
  (comint-output-filter proc (inferior-gijit-strip-ctrl-g string)))

(defun inferior-gijit-output-digest (proc string)
  "Special output filter for the inferior Gijit process.
Save all output between newlines into `inferior-gijit-output-list', and
the rest to `inferior-gijit-output-string'."
  (setq string (concat inferior-gijit-output-string string))
  (while (string-match "\n" string)
    (setq inferior-gijit-output-list
	  (append inferior-gijit-output-list
		  (list (substring string 0 (match-beginning 0))))
	  string (substring string (match-end 0))))
  (if (string-match *inferior-gijit-regex-prompt* string)
      (setq inferior-gijit-receive-in-progress nil))
  (setq inferior-gijit-output-string string))

(defun inferior-gijit-send-list-and-digest (list)
  "Send LIST to the inferior Gijit process and digest the output.
The elements of LIST have to be strings and are sent one by one.  All
output is passed to the filter `inferior-gijit-output-digest'."
  (let* ((proc inferior-gijit-process)
	 (filter (process-filter proc))
	 string)
    (set-process-filter proc 'inferior-gijit-output-digest)
    (setq inferior-gijit-output-list nil)
    (unwind-protect
	(while (setq string (car list))
	  (setq inferior-gijit-output-string nil
		inferior-gijit-receive-in-progress t)
	  (comint-send-string proc string)
	  (while inferior-gijit-receive-in-progress
	    (accept-process-output proc))
	  (setq list (cdr list)))
      (set-process-filter proc filter))))


(defun gijit-kill-buffer-function nil
  "Function run just before an GIJIT process buffer is killed.
  This simply deletes the buffers process to avoid an Emacs bug
  where the sentinel is run *after* the buffer is deleted."
  (let ((proc (get-buffer-process (current-buffer))))
    (if proc (delete-process proc))))


(defun gijit-gdb-send-input ()
  "gdb-sender(): send this current text between process-mark and point to gdb
   meant as a replacement for comint-send-input to send input to gdb instead
   our inferior process."
  (interactive)
  (let ((proc (get-buffer-process (current-buffer))))
    (if (not proc) (error "Current buffer has no process")
      (progn
        (widen)
        (let* ((pmark (process-mark proc))
               (intxt (buffer-substring pmark (point))))
            (process-send-string (get-buffer-process gud-comint-buffer) intxt)
            (process-send-string (get-buffer-process gud-comint-buffer) "\n")
            )))))




(defun gijit-send-input ()
  "gijit-send-input: send input to both comint-send-input  and  gijit-gdb-send-input"
  (interactive)
  ;;(gijit-gdb-send-input)
  (comint-send-input)
)

;;; provide ourself
(provide 'gijit-mode)

