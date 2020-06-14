provider  "aws"  {
profile = "default"
region = "us-east-2"
}

resource "null_resource" "ssh_key_gen"{
	provisioner "local-exec" {
		command = "ssh-keygen -y -t rsa -m PEM -f deployer_key -N '' "
		}
}

resource "aws_key_pair" "deployer" {
  depends_on = [
		null_resource.ssh_key_gen
]
  key_name   = "deployer_key"
  public_key = file("deployer_key.pub")
}

resource "aws_security_group" "task_1_sg" {
  name        = "task_1_sg"
  description = "This is the security group for task 1"
  vpc_id      = "vpc-0ca6203097928a193"

  ingress {
    description = "SSHConnection"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks =["0.0.0.0/0"]
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task_1_sg"
  }
}

resource "aws_instance" "task_1_instance" {
  ami           = "ami-026dea5602e368e96"
  instance_type = "t2.micro"
  key_name = "deployer_key"
  security_groups = ["${aws_security_group.task_1_sg.name}"]

connection {
  type = "ssh"
  user= "ec2-user"
  private_key = file("deployer_key.pem")
  host = aws_instance.task_1_instance.public_ip
}

provisioner "remote-exec"  {
  inline = [
	"sudo yum install httpd php git -y",
	"sudo systemctl start httpd",
	"sudo systemctl enable httpd",
	]
}
  tags = {
    Name = "task_1_instance"
  }
}
 
resource "aws_ebs_volume" "task_1_vol" {
	availability_zone = aws_instance.task_1_instance.availability_zone
	size = 1
	tags = {
		Name= "task_1_vol"
		}
}

resource "aws_volume_attachment" "task_1_attach" {
  device_name = "/dev/sdg"
  volume_id   = "${aws_ebs_volume.task_1_vol.id}"
  instance_id = "${aws_instance.task_1_instance.id}"
  force_detach = true
}

output "task_1_instance_ip"{
	value = aws_instance.task_1_instance.public_ip
}

resource "null_resource" "instance_public_ip" {
	provisioner "local-exec" {
		command = "echo ${aws_instance.task_1_instance.public_ip} >   my_ins_public_ip.txt"
	}
}
resource "null_resource" "ssh_conn" {
	depends_on = [
		aws_volume_attachment.task_1_attach
	]
	
	connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("deployer_key.pem")
    host     = aws_instance.task_1_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdg",
      "sudo mount /dev/xvdg /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Kp18136/kalpesh.git /var/www/html"
    ]
  }
}


/////S3

resource "aws_s3_bucket" "task1-s3-bucketkp" {
    bucket  = "task1-s3-bucketkp"
    acl     = "public-read"

provisioner "local-exec" {
        command     = "git clone https://github.com/Kp18136/kalpesh.git kalpesh"
    }
provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s kalpesh"
    }

}

resource "aws_s3_bucket_object" "s3-image-upload" {
    bucket  = aws_s3_bucket.task1-s3-bucketkp.bucket
    key     = "Screenshot_20181220-080051.jpg"
    source  = "kalpesh/Screenshot_20181220-080051.jpg"
    acl     = "public-read"

}
////cloudfront

variable "var1" {default = "S3-"}
locals {
    s3_origin_id = "${var.var1}${aws_s3_bucket.task1-s3-bucketkp.bucket}"
    image_url = "${aws_cloudfront_distribution.s3_task_distribute.domain_name}/${aws_s3_bucket_object.s3-image-upload.key}"
}
resource "aws_cloudfront_distribution" "s3_task_distribute" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
       min_ttl = 0
       default_ttl = 3600
       max_ttl = 86400
      compress = true
        viewer_protocol_policy = "allow-all"
    }
enabled             = true
origin {
        domain_name = aws_s3_bucket.task1-s3-bucketkp.bucket_domain_name
        origin_id   = local.s3_origin_id
    }
restrictions {
        geo_restriction {
        restriction_type = "whitelist"
        locations = ["IN"]
        }
    }
viewer_certificate {
        cloudfront_default_certificate = true
    }

connection {
type = "ssh"
user = "ec2-user"
private_key = file("deployer_key.pem")
host = aws_instance.task_1_instance.public_ip	
}


provisioner "remote-exec" {
	inline = [
	"sudo su << EOF",
	"echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.s3-image-upload.key}'>\"  >> /var/www/html/index.php",
	"EOF",
	]
}

provisioner "local-exec" {
		command = "start chrome ${aws_instance.task_1_instance.public_ip}"
	}
}      
