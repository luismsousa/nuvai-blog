---
title: "How to set up an IaC pipeline using GitHub and Terraform Cloud"
date: 2022-06-02T07:33:05Z
draft: true
---

**Before we get started:** Sometimes, cloud-based tools and technologies can be quite daunting to adopt for teams. In what I hope to be a series of blog posts, I’ll try to demystify the adoption fears and try to shed some light on a few pitfalls that you might want to avoid when considering tools. If you like this kind of content, find it useful or disagree with me, feel free to let me know by commenting below or tagging me on twitter. 😎

***

Unless you’ve had your head buried in the clouds for the past few years, you’ve probably come across the term, Infrastructure as Code (IaC). For better or for worse, Terraform is the go-to tool and it’s easy to see why. I’ll keep the reasons why it’s one of my favourite tools to use for another post, but you can see from the data below that it’s seen a meteoric rise in adoption.

#todo add picture - caption: Job postings citing Terraform as a proportion of all IT jobs advertised. Credit: ITJobsWatchUK

There are tons of tutorials on how to use Terraform, but very few of them tackle the inevitable issue of state file management head-on. Most of them rely on copy-paste code that publishes the state into an S3 bucket and tries to keep track of locks in a DynamoDB table (the equivalent would apply in Azure or GCP). This works fine in the beginning but can get messy/nightmarish quickly as soon as you add the common ingredients of any single or set of teams: team members + environments + silos (both natural and artificial).

Let me give you an example of a bad implementation that is essentially un-maintainable. Picture, if you will, a 4 AWS account structure that segregates the following logical “areas”: Infra (read tooling); Development; NonProd; Prod. In this setup, the Infra account contains your tools such as <insert CI tool of choice>, <monitoring tools>, and Terraform; with the right cross-account roles to allow the orchestration engine in infra to apply changes in a controlled fashion across the other 3 accounts.

Now imagine you have hundreds of services and infrastructure components per “environment”, each one with its state file, some of them depending on each other for outputs/dependencies and you can quickly see that maintaining thousands of JSON blobs in a folder hierarchy in S3 can quickly devolve into a “shove it in the closet and only look at it when it breaks” way of working. Not to even mention the usual drama of “my terraform pipeline has broken with a state-lock issue” because someone cancelled a job run mid-way through it.

This is where Hashicorp’s free (for small teams) Terraform Cloud offering can come into play to help massively by managing all the intricacies of state file lifecycle management and plugging in your SCM tool of choice (in this case I’m using GitHub, but I’ve also used it with Gitlab with the same result)

## The actual technical bits

Enough rambling, let’s fire up those terminals 🔥

## Pre-requisites:

Create your private (or public if you’re feeling brave) git repository to hold the IaC. I’ve set up mine with the following structure but others may be just as valid.

Create a Terraform Cloud free account here

Create your Terraform org, I’ll use acmeorg for demo purposes

Login to Terraform Cloud via the CLI by performing a terraform login command. (this will open a new window in your browser and request you to set up an “app-password”)

#todo picture

Let’s take the previous example and create a folder for each of our AWS accounts (or GCP projects) and another folder for our modules.

**Sidebar:** I’m painfully aware that this is a very simple setup and in a real-life scenario you’d want to make it so you can perform tons of different processes such as decoupling your stateful and stateless components so you can tear them down and rebuild on a need basis, or decoupling your base networks from your app and DB tiers.

Our `providers.tf` file will contain, for this example, our AWS provider for the IaaS, Cloudflare for our CDN and WAF and our Terraform State block.
For this particular scenario, and for simplicity, I won’t make use of name-prefixes for the “workspaces” functionality as that will add unnecessary complexity and merits its separate post.

```
terraform {
   backend "remote" {
      hostname     = "app.terraform.io"
      organization = "acmeorg"
      workspaces {
         name = "aws-infra"
      }
   }
}
```

And with terraform init we get the validation that our config is correct:

#todo picture

But before we can start building some amazing infra with those sweet modules you’ve just coded, we need to configure the GitHub to Terraform Integration. You can find the setup guide for your particular SCM here #todo link.

Once the provider is set up, you can connect your workspace to the repository containing your terraform code.

#todo image caption: Click “Connect to version control” and select your repository

Once you’ve done that, but now we need to tell this workspace, which folder to `cd` into when it starts a run; for that, we need to jump into the **“General Settings”** section and input our folder name in the **Terraform Working Directory** field.

#todo image: caption: Don’t forget to click Save

## Approval Gate
Terraform has a nifty little feature I’ve always chased in my custom implementations using Orchestration tools. The ability to review and comment/approve changes before they are applied is a major reason why I find this workflow so useful. By default, that feature is enabled but you can choose to have automatic applies for lower environments for example. If you wish to change it, this is the place to do it:

#todo image caption: Manual apply = Confirmation step < — | → Auto Apply = Apply if the plan is successful

## Branch Control

“But wait”, you say, “won’t this run off of my master branch?” — Yes, it will! Let’s change that.
Click on the Settings dropdown and select “Version Control”. In here, we’ll perform two changes:
1. Tell Terraform which branch to scan and trigger runs off of. — Very useful when used in conjunction with branch permissions. Use this feature if you don’t want to do trunk-based development
2. Select which folders in the repository to react to. — This is very useful if like me you like to have a mono-repo for your infrastructure.

#todo image caption For each path you want to add, you need to click the “Add Path” button on the right-hand side.

Let’s add the modules folder to our scan list so we get new changes planned if we update our modules. This assumes that the modules are co-located and not in a separate repo. This approach is better to keep your processes streamlined as every change that affects this workspace will be detected and planned for you.

If you want to use module versioning with git tags, there are a few extra steps needed. Let me know if you’d like to see that and I’ll do a separate write up. I don’t like this approach as it creates “stale” infra if they don’t get run often. Meaning you get surprised by a ton of divergence when you come back to run this particular workspace again in 6 months.

Finally, we can set your AWS/GCP credentials in the **Variables** pane so Terraform can plan and apply our changes. Select the **Sensitive** flag when dealing with secrets.

#todo image, caption Following the principle of least privilege, these credentials should only have the permissions they need, don’t go attaching “AdministratorAcess” to them :)

## Planning a change
You can now plan a change via the CLI by running the terraform plan command, you’ll see the output in your terminal like you’d usually see but this is not running from your local machine. It will run remotely in Terraform Cloud instead. More than anything else, I think this is the single most important feature of Terraform Cloud.

> By unifying all the plans and applies, we’re providing a consistent experience to all the platform engineers in the team, preventing the need for programmatic keys and elaborate setups for every user. All you need is access to the codebase and an IDE. All the network and approval flows are handled centrally.

## Applying a Change
With our configuration concluded, we’re finally ready to commit our code to the develop branch (or to a more “privileged” branch via merge request with approvals) and wait for the status indicator to show up next to our change in Github. Once your plan is complete, review it, approve it (if you have the manual approval enabled), and once it applies you should have a success checkmark next to your commit.

Clicking on this checkmark will provide you links to all the workspaces that ran this change and their status.

#todo image, caption: A screenshot of my repository

***
In essence, this is just an example of how you can get a slim workflow that balances control and efficiency around infrastructure changes. So far and in my experience, this approach has proved very convenient, powerful and simple to maintain and or onboard people to. And using the paid features such as Sentinel for compliance as code and approval gates, it allows us to throw away all the custom terraform pipelines of yesteryear and accelerate our infrastructure as code releases in an unprecedented way.

If you enjoyed these deep dives and you’d like to see more of this kind of content, leave a comment and start a discussion!