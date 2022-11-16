resource "aws_lb" "{{ name | underscorify }}_nlb" {
  name               = "{{ name | dashify }}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnets
}

resource "aws_lb_target_group" "{{ name | underscorify }}_nlb_tg" {
  name        = "{{ name | dashify }}-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "alb"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "{{ name | underscorify }}_nlb_tg_attachment" {
  target_group_arn = aws_lb_target_group.{{ name | underscorify }}_nlb_tg.arn
  # target to attach to this target group
  target_id = module.{{ name | dashify }}.lb_arn
  #  If the target type is alb, the targeted Application Load Balancer must have at least one listener whose port matches the target group port.
  port = 80
}

resource "aws_lb_listener" "{{ name }}_nlb_listener" {
  load_balancer_arn = aws_lb.{{ name | underscorify }}_nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.{{ name | underscorify }}_nlb_tg.arn
  }
}

resource "aws_api_gateway_vpc_link" "{{ name | underscorify }}_vpc_link" {
  name        = "{{ name | dashify }}-vpc-link"
  description = "allows public API Gateway to talk to private NLB"
  target_arns = [aws_lb.{{ name | underscorify }}_nlb.arn]
}

resource "aws_api_gateway_rest_api" "{{ name | underscorify }}_rest_api" {
  name = "{{ name | dashify }}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "{{ name }}_api_gw_resource" {
  rest_api_id = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  parent_id   = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "{{ name }}_api_gw_method" {
  rest_api_id      = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  resource_id      = aws_api_gateway_resource.{{ name | underscorify }}_api_gw_resource.id
  http_method      = "ANY"
  authorization    = "NONE"
  api_key_required = false
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "{{ name }}_api_gw_integration" {
  rest_api_id = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  resource_id = aws_api_gateway_resource.{{ name | underscorify }}_api_gw_resource.id
  http_method = aws_api_gateway_method.{{ name | underscorify }}_api_gw_method.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${module.{{ name }}-api.lb_dns}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.{{ name | underscorify }}_api_vpc_link.id
  timeout_milliseconds    = 29000 # 50-29000

  cache_key_parameters = ["method.request.path.proxy"]
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_method_response" "{{ name | underscorify }}_api_gw_response" {
  rest_api_id = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  resource_id = aws_api_gateway_resource.{{ name | underscorify }}_api_gw_resource.id
  http_method = aws_api_gateway_method.{{ name | underscorify }}_api_gw_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "{{ name | underscorify }}_api_gw_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  resource_id = aws_api_gateway_resource.{{ name | underscorify }}_api_gw_resource.id
  http_method = aws_api_gateway_method.{{ name | underscorify }}_api_gw_method.http_method
  status_code = aws_api_gateway_method_response.{{ name | underscorify }}_api_gw_response.status_code

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_deployment" "{{ name | underscorify }}_api_gw_deployment" {
  depends_on  = [aws_api_gateway_integration.{{ name | underscorify }}_api_gw_integration]
  rest_api_id = aws_api_gateway_rest_api.{{ name | underscorify }}_rest_api.id
  stage_name  = "v1"
}
