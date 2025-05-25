# nasto's dotfiles
## Get started and reuse this repo
This has repo has been created using the `chezmoi` project (https://www.chezmoi.io/)

If you want to reuse it, please follow the following steps
1. Install chezmoi
2. Init chezmoi using `chezmoi init https://github.com/nastoo/dotfiles.git`
3. Check what changes that chezmoi will make to your home directory by running: `chezmoi diff`
4. If you are happy with the changes that chezmoi will make then run: `chezmoi apply -v` or `chezmoi edit $FILE` if you're not happy

Then, everytime you want to, you can update the config by running `chezmoi update -v`

If you're unsure, please check the official docs: https://www.chezmoi.io/quick-start/
