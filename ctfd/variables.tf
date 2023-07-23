variable "public_key_filename" {
  type = string
  description = "The filaname to write the public key too."
}

variable "private_key_filename" {
  type = string
  description = "The filename to write the private key too."
}

variable "ctfd_hostname" {
  type = string
  description = "The hostname of the ctfd server for the A record."
}

variable "r53_zone_id" {
  type = string  
  description = "The domain zone ID for where we want to create the Route 53 records."
}
