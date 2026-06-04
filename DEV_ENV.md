# Setting Up the DEV Environment Variable

Setting up the spore development environment.
Repos are expected laterally in a location that uses DEV as an environment variable.

Below is a how-to on each system.

#### macOS
Open your shell configuration file in a text editor:
bash

nano ~/.zshrc
(If you use Bash instead, use ~/.bash_profile)
Add the following line at the end of the file:
bash

export DEV=your_value_here
Save and exit (in nano: press Ctrl+O, then Enter, then Ctrl+X)
Reload your shell configuration:
bash

source ~/.zshrc
Verify the variable was set:
bash

echo $DEV


#### Linux
Open your shell configuration file:
bash

nano ~/.bashrc
(For Zsh, use ~/.zshrc)
Add the following line at the end:
bash

export DEV=your_value_here
Save and exit (in nano: press Ctrl+O, then Enter, then Ctrl+X)
Reload your configuration:
bash

source ~/.bashrc
Verify the variable:
bash

echo $DEV


#### Windows (Command Prompt)
Press Win + R, type cmd, and press Enter
Set the environment variable temporarily (current session only):
cmd

set DEV=your_value_here
To set it permanently, use:
cmd

setx DEV "your_value_here"
Close and reopen Command Prompt to verify:
cmd

echo %DEV%


#### Windows (PowerShell)
Open PowerShell as Administrator
Set the environment variable:
powershell

[Environment]::SetEnvironmentVariable("DEV", "your_value_here", "User")
Restart PowerShell and verify:
powershell

$env:DEV