=begin
Insights Service Catalog API

This is a API to fetch and order catalog items from different cloud sources

OpenAPI spec version: 1.0.0
Contact: you@your-company.com
Generated by: https://github.com/swagger-api/swagger-codegen.git

=end


class Portfolio < ApplicationRecord
  include Discard::Model
  acts_as_tenant(:tenant)
  default_scope -> { kept }

  validates :name, :presence => true, :uniqueness => { :scope => %i(tenant_id discarded_at) }
  validates :image_url, :format => { :with => URI::DEFAULT_PARSER.make_regexp }, :allow_blank => true
  validates :enabled_before_type_cast, :format => { :with => /\A(true|false)\z/i }, :allow_blank => true

  has_many :portfolio_items, :dependent => :destroy

  before_discard do
    if portfolio_items.map(&:discard).any? { |result| result == false }
      portfolio_items.kept.each do |item|
        errors.add(item.name.to_sym, "PortfolioItem ID #{item.id}: #{item.name} failed to be discarded")
      end

      Rails.logger.error("Failed to discard items from Portfolio #{id} - not discarding portfolio")
      throw :abort
    end
  end

  def add_portfolio_item(portfolio_item_id)
    portfolio_item = PortfolioItem.find_by(id: portfolio_item_id)
    portfolio_items << portfolio_item
  end
end
