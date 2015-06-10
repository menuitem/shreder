I. Installing AWS Command Line Interface (with pip)
http://docs.aws.amazon.com/cli/latest/userguide/installing.html#install-with-pip
You will need python version 2.6.5+ or Python 3 version 3.3+
Install aws cli with pip
: $; sudo pip install awscli
: $; sudo pip install --upgrade awscli
3. Test AWS command Line Interface
: $; aws help
4. Configure AWS Command Line Interface
http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
: $; aws configure
|-------------------------------------------------------------------------------|
|AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE									|
|AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY			|
|Default region name [None]: us-west-2											|
|Default output format [None]: json												|
|-------------------------------------------------------------------------------|
You can also choose "text" as Default output format.
5. Add Command line completion for AWS Command Line Interface
http://docs.aws.amazon.com/cli/latest/userguide/cli-command-completion.html
: $; which aws_completer
/usr/local/aws/bin/aws_completer
: $; complete -C '/usr/local/aws/bin/aws_completer' aws
or run this command instead of these two above:
: $; complete -C $(which aws_completer) aws
Add autocomplete to your ~/.bashrc.
: $; echo 'complete -C $(which aws_completer) aws' >> ~/.bashrc
